const functions = require('firebase-functions')
const admin = require('firebase-admin')
const { Storage } = require('@google-cloud/storage')
const archiver = require('archiver')
const cors = require('cors')({ origin: true })

const firestore = admin.firestore()
const storage = new Storage()
const bucketName = functions.config().agora?.storage_bucket_name || 'default-bucket'

/** Signed URL lifetime: 4 hours. */
const SIGNED_URL_MS = 4 * 60 * 60 * 1000

function parseJsonBody(req) {
    let body = req.body
    if (body == null) return {}
    if (typeof body === 'string') {
        try { return JSON.parse(body) || {} } catch (_) { return {} }
    }
    return body
}

/**
 * Returns true for VTT files that are the canonical (non-language-prefixed) slice.
 *
 * Agora STT writes two copies of every time slice:
 *   1. {agentId}_{channel}_{ts}.vtt          ← raw (what we keep)
 *   2. en-US_{agentId}_{channel}_{ts}.vtt    ← language-tagged duplicate (skip)
 *
 * We keep only the non-language-prefixed files to avoid duplicate content.
 * The two copies are identical when no translation is configured.
 */
function isCanonicalVttFile(name) {
    if (!name || typeof name !== 'string') return false
    const base = name.split('/').pop() || ''
    if (!base.toLowerCase().endsWith('.vtt')) return false
    if (base.toLowerCase().includes('.tmp')) return false
    // Skip language-prefixed duplicates: files starting with e.g. "en-US_", "zh-CN_", "fr-FR_"
    if (/^[a-z]{2}-[A-Z]{2}_/.test(base)) return false
    return true
}

/**
 * Extracts unique Agora UIDs (integers) from VTT voice-tag annotations.
 * Agora writes speakers as: <v 327116469>
 */
function extractAgoraUids(vttContent) {
    const uids = new Set()
    for (const match of vttContent.matchAll(/<v (\d+)>/g)) {
        uids.add(parseInt(match[1], 10))
    }
    return uids
}

/**
 * Builds a map from Agora UID → { displayName, userId } by querying the
 * publicUser Firestore collection (field: agoraId).
 */
async function buildUidToSpeakerMap(uids) {
    const map = {}
    await Promise.all([...uids].map(async (uid) => {
        try {
            const snap = await firestore.collection('publicUser')
                .where('agoraId', '==', uid)
                .limit(1)
                .get()
            if (!snap.empty) {
                const data = snap.docs[0].data()
                const raw = data.displayName || `User-${uid}`
                // Strip characters that would break WebVTT voice tags (<v …>) or NOTE blocks:
                // > terminates a voice tag early; newlines split cues/NOTE blocks.
                const safe = raw.replace(/>/g, '\u203a').replace(/[\r\n]+/g, ' ').trim()
                map[uid] = {
                    displayName: safe || `User-${uid}`,
                    userId: snap.docs[0].id,
                }
            } else {
                map[uid] = { displayName: `User-${uid}`, userId: null }
            }
        } catch (e) {
            console.error(`Error resolving agoraId ${uid}:`, e)
            map[uid] = { displayName: `User-${uid}`, userId: null }
        }
    }))
    return map
}

/** Human-readable labels for AgreeDisagreeAnswer enum values (see pre_post_survey.dart). */
const AGREEMENT_TEXT = {
    stronglyAgree: 'Strongly agree',
    somewhatAgree: 'Somewhat agree',
    somewhatDisagree: 'Somewhat disagree',
    stronglyDisagree: 'Strongly disagree',
    unsure: 'Unsure',
}

/**
 * Returns true if the given PrePostCard (event.preEventCardData / postEventCardData)
 * has at least one survey question with actual content. Mirrors
 * PrePostSurveyQuestion.hasData in data_models/lib/events/pre_post_survey.dart.
 */
function cardHasSurveyQuestions(card) {
    const questions = card?.surveyQuestions
    if (!Array.isArray(questions)) return false
    return questions.some((q) => {
        if (!q) return false
        switch (q.type) {
            case 'agreeDisagree':
                return (q.statements || []).some(s => (s?.text || '').trim() !== '')
            case 'residence':
                return true // Question text and options are fixed in code.
            default: // multipleChoice (and unknown types decode as such)
                return (q.title || '').trim() !== '' &&
                    (q.options || []).some(o => (o?.text || '').trim() !== '')
        }
    })
}

/**
 * Fetches pre/post survey responses for the given userIds from
 * {eventPath}/pre-post-survey-responses/{userId}.
 * Returns a map: userId → { preEventAnswers, postEventAnswers } for found docs,
 * or { fetchFailed: true } when the read errored — so the legend can say
 * "unavailable" rather than falsely claiming "(no response)".
 */
async function fetchSurveyResponses(eventPath, userIds) {
    const responses = {}
    await Promise.all(userIds.map(async (userId) => {
        try {
            const snap = await firestore
                .doc(`${eventPath}/pre-post-survey-responses/${userId}`)
                .get()
            if (snap.exists) {
                const data = snap.data()
                responses[userId] = {
                    preEventAnswers: Array.isArray(data.preEventAnswers) ? data.preEventAnswers : [],
                    postEventAnswers: Array.isArray(data.postEventAnswers) ? data.postEventAnswers : [],
                }
            }
        } catch (e) {
            console.error(`Error fetching survey responses for user ${userId}:`, e)
            responses[userId] = { fetchFailed: true }
        }
    }))
    return responses
}

/**
 * Returns true if the event uses Smart Match breakout assignment with at least
 * one configured question (event.breakoutRoomDefinition.breakoutQuestions).
 */
function eventHasSmartMatch(event) {
    const def = event?.breakoutRoomDefinition
    if (!def || def.assignmentMethod !== 'smartMatch') return false
    return Array.isArray(def.breakoutQuestions) &&
        def.breakoutQuestions.some(q => (q?.title || '').trim() !== '')
}

/**
 * Fetches each speaker's Smart Match survey answers from their
 * {eventPath}/event-participants/{userId} doc (field: breakoutRoomSurveyQuestions,
 * answered at RSVP time). Returns a map: userId → { questions } for found docs,
 * or { fetchFailed: true } when the read errored.
 */
async function fetchSmartMatchAnswers(eventPath, userIds) {
    const answers = {}
    await Promise.all(userIds.map(async (userId) => {
        try {
            const snap = await firestore
                .doc(`${eventPath}/event-participants/${userId}`)
                .get()
            if (snap.exists) {
                const questions = snap.data().breakoutRoomSurveyQuestions
                answers[userId] = { questions: Array.isArray(questions) ? questions : [] }
            }
        } catch (e) {
            console.error(`Error fetching smart match answers for user ${userId}:`, e)
            answers[userId] = { fetchFailed: true }
        }
    }))
    return answers
}

/**
 * Formats Smart Match answers as "question: answer" lines. Each BreakoutQuestion
 * stores the selected answerOptionId; the option title is resolved by scanning
 * the question's answer groups.
 */
function formatSmartMatchAnswerLines(questions) {
    const lines = []
    for (const q of questions || []) {
        if (!q || (q.title || '').trim() === '') continue
        let selectedTitle = null
        if (q.answerOptionId) {
            for (const answer of q.answers || []) {
                const opt = (answer?.options || []).find(o => o?.id === q.answerOptionId)
                if (opt) { selectedTitle = opt.title; break }
            }
        }
        const question = vttNoteSafe(q.title)
        const answerText = vttNoteSafe(selectedTitle) || '(no answer)'
        lines.push(`   ${question}: ${answerText}`)
    }
    return lines
}

/** Sanitizes free text for inclusion in a WebVTT NOTE block (single line, no cue-timing arrow). */
function vttNoteSafe(text) {
    return String(text || '')
        .replace(/[\r\n]+/g, ' ')
        .replace(/-->/g, '→')
        .trim()
}

/**
 * Formats one survey answer as "question: answer" lines for the speaker legend.
 * Multiple choice / residence answers use optionText; agree/disagree answers
 * use the human-readable agreement label.
 */
function formatSurveyAnswerLines(answers) {
    const lines = []
    for (const a of answers) {
        if (!a) continue
        const question = vttNoteSafe(a.questionText) || '(question unavailable)'
        let answer
        if (a.questionType === 'agreeDisagree') {
            answer = AGREEMENT_TEXT[a.agreement] || vttNoteSafe(a.agreement) || '(no answer)'
        } else {
            answer = vttNoteSafe(a.optionText) || '(no answer)'
        }
        lines.push(`   ${question}: ${answer}`)
    }
    return lines
}

/**
 * Rewrites VTT content, replacing bare Agora UIDs with human-readable speaker labels.
 *   Before: <v 327116469>
 *   After:  <v Scott (327116469)>
 */
function enrichVttSpeakers(content, uidToSpeaker) {
    return content.replace(/<v (\d+)>/g, (_, uid) => {
        const speaker = uidToSpeaker[parseInt(uid, 10)]
        if (!speaker) return `<v User-${uid}>`
        return `<v ${speaker.displayName} (${uid})>`
    })
}

/**
 * Builds a speaker legend block to prepend to each enriched VTT file.
 * Lists every unique speaker seen in the file, and — when the event has a
 * pre and/or post survey enabled — each speaker's survey answers.
 *
 * A blank line terminates a WebVTT NOTE block, so each speaker gets its own
 * NOTE block: this yields blank-line separation between speakers while
 * keeping the file spec-valid.
 *
 * @param surveyInfo { enabled: {pre, post, smartMatch}, responsesByUserId,
 *        smartMatchByUserId } or null when no survey is enabled for the event.
 */
function buildSpeakerLegend(content, uidToSpeaker, surveyInfo) {
    const seen = new Set()
    for (const match of content.matchAll(/<v (\d+)>/g)) {
        seen.add(parseInt(match[1], 10))
    }
    if (seen.size === 0) return ''

    const includeSurveys = !!(surveyInfo &&
        (surveyInfo.enabled.pre || surveyInfo.enabled.post || surveyInfo.enabled.smartMatch))

    // CRLF matches Agora's VTT output (WebVTT spec §6.1).
    if (!includeSurveys) {
        const lines = ['NOTE Speaker legend:']
        for (const uid of seen) {
            const speaker = uidToSpeaker[uid]
            const name = speaker ? speaker.displayName : `User-${uid}`
            lines.push(`  ${name}  (Agora UID: ${uid})`)
        }
        return lines.join('\r\n') + '\r\n\r\n'
    }

    const blocks = []
    for (const uid of seen) {
        const speaker = uidToSpeaker[uid]
        const name = speaker ? speaker.displayName : `User-${uid}`
        const lines = [blocks.length === 0 ? 'NOTE Speaker legend:' : 'NOTE']
        lines.push(`  ${name}  (Agora UID: ${uid})`)

        const userId = speaker?.userId || null
        const response = userId ? surveyInfo.responsesByUserId[userId] : null
        // Distinguish "doc read errored" from "user genuinely didn't answer".
        const emptyLabel = response?.fetchFailed
            ? '   (responses unavailable — fetch error)'
            : '   (no response)'
        if (surveyInfo.enabled.smartMatch) {
            const smartMatch = userId ? surveyInfo.smartMatchByUserId[userId] : null
            lines.push('  Smart Match Answers:')
            const answerLines = formatSmartMatchAnswerLines(smartMatch?.questions || [])
            lines.push(...(answerLines.length > 0 ? answerLines : [
                smartMatch?.fetchFailed
                    ? '   (responses unavailable — fetch error)'
                    : '   (no response)',
            ]))
        }
        if (surveyInfo.enabled.pre) {
            lines.push('  Pre-Survey Answers:')
            const answerLines = formatSurveyAnswerLines(response?.preEventAnswers || [])
            lines.push(...(answerLines.length > 0 ? answerLines : [emptyLabel]))
        }
        if (surveyInfo.enabled.post) {
            lines.push('  Post-Survey Answers:')
            const answerLines = formatSurveyAnswerLines(response?.postEventAnswers || [])
            lines.push(...(answerLines.length > 0 ? answerLines : [emptyLabel]))
        }
        blocks.push(lines.join('\r\n'))
    }
    return blocks.join('\r\n\r\n') + '\r\n\r\n'
}

/**
 * downloadTranscription
 *
 * Lists Agora STT VTT files for the event (main room + breakouts), deduplicates
 * Agora's per-slice double-write (raw + language-tagged copies), resolves each
 * speaker's Agora UID to a publicUser.displayName, rewrites the VTT voice tags
 * to include the human-readable name, zips everything, uploads to a temp GCS
 * path, and returns a 4-hour signed URL.
 *
 * When the event has a pre and/or post survey enabled (event.preEventCardData /
 * postEventCardData with survey questions), each speaker's legend entry also
 * includes their survey answers from {eventPath}/pre-post-survey-responses.
 */
const downloadTranscription = functions.runWith({
    timeoutSeconds: 540,
    memory: '2GB',
    maxInstances: 10,
}).https.onRequest((req, res) => {
    cors(req, res, async () => {
        try {
            console.log('=== DOWNLOAD TRANSCRIPTION CALLED ===')

            const authToken = req.headers.authorization?.split('Bearer ')[1]
            if (!authToken) {
                res.status(401).json({ error: 'Unauthorized', code: 'NO_TOKEN' })
                return
            }

            const decodedToken = await admin.auth().verifyIdToken(authToken)
            const uid = decodedToken.uid

            const body = parseJsonBody(req)
            const { eventPath, checkOnly } = body

            if (!eventPath) {
                res.status(400).json({ error: 'Bad Request: eventPath required', code: 'MISSING_EVENT_PATH' })
                return
            }

            // Validate path shape before reading: must be the canonical events subcollection path.
            // Prevents authenticated users from probing arbitrary Firestore document existence.
            const EVENT_PATH_RE = /^community\/[^/]+\/templates\/[^/]+\/events\/[^/]+$/
            if (!EVENT_PATH_RE.test(eventPath)) {
                res.status(400).json({ error: 'Bad Request: invalid eventPath', code: 'INVALID_EVENT_PATH' })
                return
            }

            const eventDoc = await firestore.doc(eventPath).get()
            if (!eventDoc.exists) {
                res.status(404).json({ error: 'Event not found', code: 'EVENT_NOT_FOUND' })
                return
            }
            const event = { id: eventDoc.id, ...eventDoc.data() }

            const membershipDoc = await firestore.doc(
                `memberships/${uid}/community-membership/${event.communityId}`
            ).get()
            if (!membershipDoc.exists || !['owner', 'admin'].includes(membershipDoc.data().status)) {
                res.status(403).json({ error: 'Forbidden', code: 'NOT_ADMIN' })
                return
            }

            const bucket = storage.bucket(bucketName)
            const isCheckOnly = checkOnly === true

            // Collect GCS prefixes for main room and all breakout rooms.
            // Sessions are fetched in parallel to avoid N serial Firestore round-trips.
            const prefixes = [`stt/${event.id}/`]
            try {
                const liveMeetingPath = `${eventPath}/live-meetings/${event.id}`
                const sessionsSnap = await firestore.collection(`${liveMeetingPath}/breakout-room-sessions`).get()
                await Promise.all(sessionsSnap.docs.map(async (sessionDoc) => {
                    const roomsSnap = await firestore
                        .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionDoc.id}/breakout-rooms`)
                        .get()
                    roomsSnap.docs.forEach(roomDoc => {
                        const room = roomDoc.data()
                        if (room.roomId) prefixes.push(`stt/${room.roomId}/`)
                    })
                }))
            } catch (err) {
                console.error('Error fetching breakout rooms:', err)
            }

            console.log(`Searching STT prefixes: ${prefixes.join(', ')}`)

            // List canonical (non-duplicate) VTT files across all rooms.
            // checkOnly uses a paginated first-page probe (50 results) per prefix and
            // exits as soon as one canonical file is confirmed, avoiding a full listing
            // across all room prefixes just to answer "do any files exist?".
            // If the first page contains only language-tagged duplicates, fall back to
            // a full listing for that prefix before moving to the next.
            const canonicalFiles = []
            for (const prefix of prefixes) {
                if (isCheckOnly && canonicalFiles.length > 0) break
                try {
                    if (isCheckOnly) {
                        const [firstPage, nextQuery] = await bucket.getFiles({
                            prefix,
                            maxResults: 50,
                            autoPaginate: false,
                        })
                        const pageVtts = firstPage.filter(f => isCanonicalVttFile(f.name))
                        if (pageVtts.length > 0) {
                            canonicalFiles.push(...pageVtts)
                        } else if (nextQuery) {
                            // First page was all duplicates; scan further with a bounded limit.
                            // Do NOT reuse nextQuery: it inherits autoPaginate:false + maxResults:50.
                            // 200 results covers ~100 slices (2 files/slice) — sufficient for
                            // events up to ~100 minutes per room.
                            const [allFiles] = await bucket.getFiles({ prefix, maxResults: 200 })
                            canonicalFiles.push(...allFiles.filter(f => isCanonicalVttFile(f.name)))
                        }
                    } else {
                        const [files] = await bucket.getFiles({ prefix })
                        const vtts = files.filter(f => isCanonicalVttFile(f.name))
                        canonicalFiles.push(...vtts)
                        console.log(`Prefix ${prefix}: ${files.length} total, ${vtts.length} canonical VTTs`)
                    }
                } catch (err) {
                    console.error(`Error listing ${prefix}:`, err)
                }
            }

            console.log(`Total canonical VTT files: ${canonicalFiles.length}`)

            if (canonicalFiles.length === 0) {
                res.status(404).json({
                    error: 'No transcription files found',
                    code: 'NO_TRANSCRIPTIONS',
                    detail: `No VTT files under stt/ prefixes in gs://${bucketName}.`,
                })
                return
            }

            if (isCheckOnly) {
                res.status(200).json({ available: true, fileCount: canonicalFiles.length })
                return
            }

            // Download VTT contents in bounded batches to keep peak memory constant
            // regardless of event size (large events with many breakout rooms).
            console.log('Downloading VTT file contents...')
            const DOWNLOAD_BATCH = 50
            const fileContents = []
            for (let i = 0; i < canonicalFiles.length; i += DOWNLOAD_BATCH) {
                const batch = canonicalFiles.slice(i, i + DOWNLOAD_BATCH)
                const results = await Promise.all(
                    batch.map(async (file) => {
                        const [buf] = await file.download()
                        return { file, content: buf.toString('utf8') }
                    })
                )
                fileContents.push(...results)
            }

            // Collect all unique Agora UIDs across all files
            const allUids = new Set()
            for (const { content } of fileContents) {
                for (const uid of extractAgoraUids(content)) allUids.add(uid)
            }
            console.log(`Resolving ${allUids.size} unique Agora UID(s):`, [...allUids])

            // Resolve Agora UIDs to displayNames via publicUser collection
            const uidToSpeaker = await buildUidToSpeakerMap(allUids)
            console.log(`Resolved ${Object.keys(uidToSpeaker).length} speaker(s)`)

            // If the event has pre/post surveys and/or Smart Match questions
            // enabled, fetch each speaker's answers for the legend.
            const surveyEnabled = {
                pre: cardHasSurveyQuestions(event.preEventCardData),
                post: cardHasSurveyQuestions(event.postEventCardData),
                smartMatch: eventHasSmartMatch(event),
            }
            let surveyInfo = null
            if (surveyEnabled.pre || surveyEnabled.post || surveyEnabled.smartMatch) {
                const speakerUserIds = [...new Set(
                    Object.values(uidToSpeaker).map(s => s.userId).filter(Boolean)
                )]
                const [responsesByUserId, smartMatchByUserId] = await Promise.all([
                    (surveyEnabled.pre || surveyEnabled.post)
                        ? fetchSurveyResponses(eventPath, speakerUserIds)
                        : {},
                    surveyEnabled.smartMatch
                        ? fetchSmartMatchAnswers(eventPath, speakerUserIds)
                        : {},
                ])
                surveyInfo = { enabled: surveyEnabled, responsesByUserId, smartMatchByUserId }
                console.log(
                    `Surveys enabled (pre=${surveyEnabled.pre}, post=${surveyEnabled.post}, ` +
                    `smartMatch=${surveyEnabled.smartMatch}); fetched ` +
                    `${Object.keys(responsesByUserId).length} pre/post response doc(s) and ` +
                    `${Object.keys(smartMatchByUserId).length} participant doc(s) ` +
                    `for ${speakerUserIds.length} speaker(s)`
                )
            }

            // Fixed path per event — overwrites on re-download (no timestamp suffix).
            // Do NOT delete after signing: the signed URL becomes a 404 the moment the
            // object is removed. Cleanup relies on a GCS Object Lifecycle rule that
            // deletes objects under temp-downloads/ after 1 day.
            // Setup: see docs/GCS_LIFECYCLE_RULES.md
            const zipFileName = `temp-downloads/${event.id}/transcriptions.zip`
            const zipFile = bucket.file(zipFileName)
            const writeStream = zipFile.createWriteStream({
                metadata: { contentType: 'application/zip' },
            })

            await new Promise((resolve, reject) => {
                const archive = archiver('zip', { zlib: { level: 6 } })
                archive.on('error', reject)
                archive.on('warning', (warn) => console.warn('archiver warning:', warn))
                writeStream.on('error', reject)
                writeStream.on('finish', resolve)
                archive.pipe(writeStream)

                for (const { file, content } of fileContents) {
                    const legend = buildSpeakerLegend(content, uidToSpeaker, surveyInfo)
                    const enriched = enrichVttSpeakers(content, uidToSpeaker)
                    // Capture the actual line ending (LF or CRLF — Agora uses CRLF per WebVTT spec)
                    // so the legend is injected with the same newline style as the rest of the file.
                    const finalContent = enriched.startsWith('WEBVTT')
                        ? enriched.replace(/^WEBVTT([^\r\n]*)(\r?\n)/, (_, title, eol) => `WEBVTT${title}${eol}${eol}${legend}`)
                        : legend + enriched

                    // Preserve room subfolder but strip stt/ prefix for cleaner zip structure
                    const parts = file.name.split('/')
                    // parts: ["stt", "{roomId}", "{filename}.vtt"]
                    const zipPath = parts.slice(1).join('/')  // "{roomId}/{filename}.vtt"
                    archive.append(Buffer.from(finalContent, 'utf8'), { name: zipPath })
                }

                archive.finalize()
            })

            console.log(`Zip written to gs://${bucketName}/${zipFileName}`)

            const [signedUrl] = await zipFile.getSignedUrl({
                action: 'read',
                expires: Date.now() + SIGNED_URL_MS,
            })
            const [meta] = await zipFile.getMetadata()
            const totalSizeMB = Math.round(parseInt(meta.size || 0) / (1024 * 1024))

            // Build a human-readable speaker summary for the response message
            const speakerSummary = Object.values(uidToSpeaker)
                .map(s => s.displayName)
                .filter((v, i, a) => a.indexOf(v) === i)
                .join(', ')

            res.status(200).json({
                mode: 'zip',
                url: signedUrl,
                fileName: `transcriptions_${event.id}.zip`,
                fileCount: canonicalFiles.length,
                totalSizeMB,
                speakers: Object.fromEntries(
                    Object.entries(uidToSpeaker).map(([uid, s]) => [uid, s.displayName])
                ),
                message: `${canonicalFiles.length} transcript slice(s) — speakers: ${speakerSummary || 'unknown'}. ` +
                    'Each VTT file includes a speaker legend with displayName → Agora UID.',
            })
        } catch (err) {
            console.error('Error in downloadTranscription:', err)
            if (!res.headersSent) {
                res.status(500).json({ error: 'Internal Server Error', code: 'INTERNAL' })
            }
        }
    })
})

module.exports = downloadTranscription
