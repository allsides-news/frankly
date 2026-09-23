const functions = require('firebase-functions')
const admin = require('firebase-admin')
const { Storage } = require('@google-cloud/storage')
const cors = require('cors')({ origin: true })

const firestore = admin.firestore()
const storage = new Storage()
const bucketName = functions.config().agora?.storage_bucket_name || 'default-bucket'

/** Long enough for sequential downloads (see events_tab delays). */
const SIGNED_URL_MS = 8 * 60 * 60 * 1000

function parseJsonBody(req) {
    let body = req.body
    if (body == null) return {}
    if (typeof body === 'string') {
        try {
            return JSON.parse(body) || {}
        } catch (_) {
            return {}
        }
    }
    return body
}

function isDeliverableRecordingObject(name) {
    if (!name || typeof name !== 'string') return false
    const base = name.split('/').pop() || ''
    const lower = base.toLowerCase()
    if (!lower.endsWith('.mp4')) return false
    if (lower.includes('.tmp')) return false
    return true
}

// Always returns signed URLs for original MP4s (no server ZIP, no client-side ZIP).
const downloadRecording = functions.runWith({
    timeoutSeconds: 540,
    memory: '8GB',
    maxInstances: 10,
}).https.onRequest((req, res) => {
    cors(req, res, async () => {
        try {
            console.error('=== DOWNLOAD RECORDING FUNCTION CALLED ===')

            const authToken = req.headers.authorization?.split('Bearer ')[1]
            if (!authToken) {
                console.error('No auth token provided')
                res.status(401).json({ error: 'Unauthorized: No auth token provided' })
                return
            }

            const decodedToken = await admin.auth().verifyIdToken(authToken)
            const uid = decodedToken.uid
            console.error(`User authenticated: ${uid}`)

            const body = parseJsonBody(req)
            const { eventPath, checkOnly } = body
            console.error(`downloadRecording called - eventPath: ${eventPath}, uid: ${uid}`)

            if (!eventPath) {
                console.error('No eventPath provided in request body')
                res.status(400).json({ error: 'Bad Request: eventPath not found', code: 'MISSING_EVENT_PATH' })
                return
            }

            console.log(`Fetching event document: ${eventPath}`)
            const eventDoc = await firestore.doc(eventPath).get()
            if (!eventDoc.exists) {
                console.error(`Event not found at path: ${eventPath} (Firestore DB must match client FIREBASE_DATABASE_ID / app.firebase_database_id)`)
                res.status(404).json({ error: 'Not Found: event not found', code: 'EVENT_NOT_FOUND' })
                return
            }
            const event = { id: eventDoc.id, ...eventDoc.data() }
            console.log(`Event found: ${event.id}, communityId: ${event.communityId}`)

            const membershipPath = `memberships/${uid}/community-membership/${event.communityId}`
            const membershipDoc = await firestore.doc(membershipPath).get()
            if (!membershipDoc.exists) {
                res.status(403).json({ error: 'Forbidden: membership not found', code: 'NO_MEMBERSHIP' })
                return
            }
            const membership = membershipDoc.data()

            if (!['owner', 'admin'].includes(membership.status)) {
                res.status(403).json({ error: 'Forbidden: Unauthorized', code: 'NOT_ADMIN' })
                return
            }

            const bucket = storage.bucket(bucketName)

            console.log(`Searching for recordings for event: ${event.id}`)

            const isCheckOnly = checkOnly === true
            // checkOnly: minimal listing – we only need at least one file, not a full inventory.
            const listOpts = isCheckOnly ? { maxResults: 500 } : {}

            const [mainRoomFiles] = await bucket.getFiles({ prefix: `${event.id}/`, ...listOpts })
            const mainRoomMp4s = mainRoomFiles.filter(f => isDeliverableRecordingObject(f.name))

            console.log(`Found ${mainRoomMp4s.length} main room MP4 files`)

            let breakoutMp4s = []
            const needBreakoutScan = !isCheckOnly || mainRoomMp4s.length === 0

            if (needBreakoutScan) {
                const breakoutRoomIds = []
                try {
                    const liveMeetingPath = `${eventPath}/live-meetings/${event.id}`
                    console.log(`Looking for breakout sessions at: ${liveMeetingPath}/breakout-room-sessions`)

                    const sessionsSnapshot = await firestore.collection(`${liveMeetingPath}/breakout-room-sessions`).get()
                    console.log(`Found ${sessionsSnapshot.docs.length} breakout session(s)`)

                    for (const sessionDoc of sessionsSnapshot.docs) {
                        const roomsSnapshot = await firestore
                            .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionDoc.id}/breakout-rooms`)
                            .get()

                        roomsSnapshot.docs.forEach(roomDoc => {
                            const room = roomDoc.data()
                            if (room.roomId) {
                                breakoutRoomIds.push(room.roomId)
                            }
                        })
                    }

                    console.log(`Total breakout room IDs found: ${breakoutRoomIds.length}`, breakoutRoomIds)
                } catch (err) {
                    console.error('Error fetching breakout rooms:', err)
                }

                const breakoutResults = await Promise.all(
                    breakoutRoomIds.map(async (roomId) => {
                        try {
                            const [roomFiles] = await bucket.getFiles({ prefix: `${roomId}/`, ...listOpts })
                            return roomFiles.filter(f => isDeliverableRecordingObject(f.name))
                        } catch (err) {
                            console.error(`Error fetching files for room ${roomId}:`, err)
                            return []
                        }
                    }),
                )
                breakoutMp4s = breakoutResults.flat()
            } else {
                console.log('checkOnly: skipping breakout GCS listing (main room already has deliverable MP4s)')
            }

            const mp4Files = [...mainRoomMp4s, ...breakoutMp4s]

            console.log(`Total: ${mp4Files.length} MP4 files (${mainRoomMp4s.length} main + ${breakoutMp4s.length} breakout)`)
            if (mp4Files.length > 0) {
                console.log('Sample file names:', mp4Files.slice(0, 5).map(f => f.name))
            }

            if (mp4Files.length === 0) {
                console.error(`NO MP4 FILES FOUND! Main candidates: ${mainRoomFiles.length}, Breakout: ${breakoutMp4s.length}`)
                res.status(404).json({
                    error: 'No recordings found',
                    code: 'NO_RECORDINGS',
                    detail: `No .mp4 objects under gs://${bucketName}/${event.id}/ or breakout room prefixes.`,
                })
                return
            }

            // checkOnly: caller just wants to know if files exist (no signed URLs needed)
            if (isCheckOnly) {
                console.log(`checkOnly=true, returning availability for ${mp4Files.length} file(s)`)
                res.status(200).json({
                    available: true,
                    fileCount: mp4Files.length,
                })
                return
            }

            const filesWithUrls = await Promise.all(mp4Files.map(async (file) => {
                const [meta] = await file.getMetadata()
                const [signedUrl] = await file.getSignedUrl({
                    action: 'read',
                    expires: Date.now() + SIGNED_URL_MS,
                })
                const parts = file.name.split('/')
                const basename = parts.pop()
                // Prefix with room ID so breakout recordings with identical basenames
                // don't collide on the client (browser auto-renames or silently overwrites).
                const roomPrefix = parts.length > 0 ? parts[0] : null
                const name = roomPrefix ? `${roomPrefix}_${basename}` : basename
                return {
                    name,
                    url: signedUrl,
                    size: parseInt(meta.size || 0),
                }
            }))

            let totalSize = 0
            for (const f of filesWithUrls) totalSize += f.size
            const estimatedSizeMB = Math.round(totalSize / (1024 * 1024))

            console.log(`Total size: ${estimatedSizeMB}MB for ${mp4Files.length} files`)

            console.log(`Returning ${filesWithUrls.length} signed URLs (original files, no ZIP)`)
            res.status(200).json({
                mode: 'individual',
                files: filesWithUrls,
                totalFiles: filesWithUrls.length,
                totalSizeMB: estimatedSizeMB,
                message:
                    `${filesWithUrls.length} file(s), ~${estimatedSizeMB}MB. ` +
                    'Each file downloads separately (original MP4s, not packaged).',
            })
        } catch (err) {
            console.error('Error processing request:', err)
            if (!res.headersSent) {
                res.status(500).json({
                    error: 'Internal Server Error',
                    details: err.message,
                    code: 'INTERNAL',
                })
            }
        }
    })
})

module.exports = downloadRecording
