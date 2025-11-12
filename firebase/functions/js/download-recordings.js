const functions = require('firebase-functions')
const admin = require('firebase-admin')
const { Storage } = require('@google-cloud/storage')
const archiver = require('archiver')
const cors = require('cors')({ origin: true })

const firestore = admin.firestore()
const storage = new Storage()
const bucketName = functions.config().agora?.storage_bucket_name || 'default-bucket'

// Main endpoint - initiates ZIP creation or returns existing job status
const downloadRecording = functions.runWith({ 
    timeoutSeconds: 540,
    memory: '8GB', // Maximum memory = more CPU and network bandwidth
    maxInstances: 10, // Prevent rate limit issues by capping concurrent instances
}).https.onRequest((req, res) => {
    cors(req, res, async () => {
        try {
            console.error('=== DOWNLOAD RECORDING FUNCTION CALLED ===')
            
            // Verify authentication
            const authToken = req.headers.authorization?.split('Bearer ')[1]
            if (!authToken) {
                console.error('No auth token provided')
                res.status(401).json({ error: 'Unauthorized: No auth token provided' })
                return
            }

            const decodedToken = await admin.auth().verifyIdToken(authToken)
            const uid = decodedToken.uid
            console.error(`User authenticated: ${uid}`)

            // Extract the eventPath from the request body
            const { eventPath } = req.body
            console.error(`downloadRecording called - eventPath: ${eventPath}, uid: ${uid}`)
            
            if (!eventPath) {
                console.error('No eventPath provided in request body')
                res.status(400).json({ error: 'Bad Request: eventPath not found' })
                return
            }

            // Fetch the event object
            console.log(`Fetching event document: ${eventPath}`)
            const eventDoc = await firestore.doc(eventPath).get()
            if (!eventDoc.exists) {
                console.error(`Event not found at path: ${eventPath}`)
                res.status(404).json({ error: 'Not Found: event not found' })
                return
            }
            const event = { id: eventDoc.id, ...eventDoc.data() }
            console.log(`Event found: ${event.id}, communityId: ${event.communityId}`)

            // Verify user has admin access
            const membershipPath = `memberships/${uid}/community-membership/${event.communityId}`
            const membershipDoc = await firestore.doc(membershipPath).get()
            if (!membershipDoc.exists) {
                res.status(403).json({ error: 'Forbidden: membership not found' })
                return
            }
            const membership = membershipDoc.data()

            if (!['owner', 'admin'].includes(membership.status)) {
                res.status(403).json({ error: 'Forbidden: Unauthorized' })
                return
            }

            // Check for existing job in Firestore
            const jobDocRef = firestore.doc(`recordingJobs/${event.id}`)
            const jobDoc = await jobDocRef.get()
            
            if (jobDoc.exists) {
                const jobData = jobDoc.data()
                
                // If completed and URL still valid (within 24 hours), return it
                if (jobData.status === 'completed' && jobData.downloadUrl) {
                    const completedAt = jobData.completedAt?.toDate() || new Date(0)
                    const hoursSinceCompletion = (Date.now() - completedAt.getTime()) / (1000 * 60 * 60)
                    
                    if (hoursSinceCompletion < 24) {
                        res.status(200).json({
                            jobId: event.id,
                            status: 'completed',
                            downloadUrl: jobData.downloadUrl,
                            fileCount: jobData.fileCount,
                            estimatedSizeMB: jobData.estimatedSizeMB
                        })
                        return
                    }
                }
                
                // If job is in progress, check if it's stale
                if (jobData.status === 'processing') {
                    const createdAt = jobData.createdAt?.toDate() || new Date(0)
                    const minutesSinceCreation = (Date.now() - createdAt.getTime()) / (1000 * 60)
                    
                    // If job has been processing for more than 15 minutes, consider it stale and restart
                    if (minutesSinceCreation > 15) {
                        console.log(`Job for event ${event.id} is stale (${minutesSinceCreation} minutes old), restarting...`)
                        // Fall through to create a new job
                    } else {
                        // Job is still actively processing
                        res.status(200).json({
                            jobId: event.id,
                            status: 'processing',
                            progress: jobData.progress || 0,
                            message: jobData.message || 'Creating ZIP file...',
                            fileCount: jobData.fileCount,
                            estimatedSizeMB: jobData.estimatedSizeMB
                        })
                        return
                    }
                }
            }

            // Count files and estimate size
            // Search for recordings from both main room and breakout rooms
            // Main room files: {eventId}/*.mp4
            // Breakout room files: {breakoutRoomId}/*.mp4 (we look up room IDs from Firestore)
            const bucket = storage.bucket(bucketName)
            
            console.log(`Searching for recordings for event: ${event.id}`)
            
            // First, get main room recordings
            const [mainRoomFiles] = await bucket.getFiles({ prefix: `${event.id}/` })
            const mainRoomMp4s = mainRoomFiles.filter(f => f.name.endsWith('.mp4'))
            
            console.log(`Found ${mainRoomMp4s.length} main room MP4 files`)
            
            // Get breakout room IDs from Firestore
            const breakoutRoomIds = []
            try {
                const liveMeetingPath = `${eventPath}/live-meetings/${event.id}`
                console.log(`Looking for breakout sessions at: ${liveMeetingPath}/breakout-room-sessions`)
                
                const sessionsSnapshot = await firestore.collection(`${liveMeetingPath}/breakout-room-sessions`).get()
                console.log(`Found ${sessionsSnapshot.docs.length} breakout session(s)`)
                
                for (const sessionDoc of sessionsSnapshot.docs) {
                    console.log(`Checking session: ${sessionDoc.id}`)
                    const roomsSnapshot = await firestore
                        .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionDoc.id}/breakout-rooms`)
                        .get()
                    console.log(`  Found ${roomsSnapshot.docs.length} room(s) in session`)
                    
                    roomsSnapshot.docs.forEach(roomDoc => {
                        const room = roomDoc.data()
                        if (room.roomId) {
                            console.log(`    Adding room ID: ${room.roomId}`)
                            breakoutRoomIds.push(room.roomId)
                        }
                    })
                }
                
                console.log(`Total breakout room IDs found: ${breakoutRoomIds.length}`, breakoutRoomIds)
            } catch (err) {
                console.error('Error fetching breakout rooms:', err)
            }
            
            // Search for recordings from each breakout room
            const breakoutMp4s = []
            for (const roomId of breakoutRoomIds) {
                try {
                    const [roomFiles] = await bucket.getFiles({ prefix: `${roomId}/` })
                    const roomMp4s = roomFiles.filter(f => f.name.endsWith('.mp4'))
                    breakoutMp4s.push(...roomMp4s)
                    if (roomMp4s.length > 0) {
                        console.log(`Found ${roomMp4s.length} MP4 files for breakout room ${roomId}`)
                    }
                } catch (err) {
                    console.error(`Error fetching files for room ${roomId}:`, err)
                }
            }
            
            // Combine all MP4 files
            const mp4Files = [...mainRoomMp4s, ...breakoutMp4s]
            
            console.log(`Total: ${mp4Files.length} MP4 files (${mainRoomMp4s.length} main + ${breakoutMp4s.length} breakout)`)
            if (mp4Files.length > 0) {
                console.log('Sample file names:', mp4Files.slice(0, 5).map(f => f.name))
            }
            
            if (mp4Files.length === 0) {
                console.error(`NO MP4 FILES FOUND! Main: ${mainRoomMp4s.length}, Breakout: ${breakoutMp4s.length}`)
                console.error(`Breakout room IDs searched:`, breakoutRoomIds)
                res.status(404).json({ error: 'No recordings found' })
                return
            }

            // Calculate actual total size
            let totalSize = 0
            for (const file of mp4Files) {
                const [metadata] = await file.getMetadata()
                totalSize += parseInt(metadata.size || 0)
            }
            const estimatedSizeMB = Math.round(totalSize / (1024 * 1024))
            
            console.log(`Total size: ${estimatedSizeMB}MB for ${mp4Files.length} files`)
            
            // Three-tier strategy:
            // 1. <= 10MB: Server-side ZIP (fast, reliable)
            // 2. 10-150MB: Client-side ZIP (good browser support)
            // 3. > 150MB: Individual downloads (avoid browser memory issues)
            const SERVER_ZIP_THRESHOLD_MB = 10
            const BROWSER_MEMORY_LIMIT_MB = 150 // Browser can't handle ZIP creation for files this large
            
            // For very large files (>150MB), provide individual download links
            // Browser runs out of memory trying to ZIP large video files
            if (estimatedSizeMB > BROWSER_MEMORY_LIMIT_MB) {
                console.log(`Size ${estimatedSizeMB}MB exceeds ${BROWSER_MEMORY_LIMIT_MB}MB - providing individual download links to avoid browser memory issues`)
                
                // Generate signed URLs for each file
                // Valid for 8 hours to accommodate large-scale downloads (2500 files @ 5 sec/file = ~3.5 hours)
                // Plus buffer time for user interruptions and retries
                const filesWithUrls = await Promise.all(mp4Files.map(async (file) => {
                    const [signedUrl] = await file.getSignedUrl({
                        action: 'read',
                        expires: Date.now() + 8 * 60 * 60 * 1000, // 8 hours
                    })
                    return {
                        name: file.name.split('/').pop(), // Just filename
                        url: signedUrl,
                        size: parseInt((await file.getMetadata())[0].size || 0)
                    }
                }))
                
                console.log(`Returning ${filesWithUrls.length} individual download URLs (no ZIP)`)
                console.log(`URLs valid for 8 hours to accommodate sequential downloads with 5-second delays`)
                res.status(200).json({
                    mode: 'individual', // Tell client to download files individually, NOT ZIP them
                    files: filesWithUrls,
                    totalFiles: filesWithUrls.length,
                    totalSizeMB: estimatedSizeMB,
                    message: `Recording is ${estimatedSizeMB}MB. Files will download individually.`
                })
                return
            }
            
            // For medium files (10-150MB), return signed URLs for client-side ZIP
            if (estimatedSizeMB > SERVER_ZIP_THRESHOLD_MB) {
                console.log(`Size ${estimatedSizeMB}MB in range ${SERVER_ZIP_THRESHOLD_MB}-${BROWSER_MEMORY_LIMIT_MB}MB - returning signed URLs for client-side ZIP`)
                
                // Generate signed URLs for each file (valid for 1 hour)
                const filesWithUrls = await Promise.all(mp4Files.map(async (file) => {
                    const [signedUrl] = await file.getSignedUrl({
                        action: 'read',
                        expires: Date.now() + 60 * 60 * 1000, // 1 hour
                    })
                    return {
                        name: file.name.split('/').pop(), // Just filename
                        url: signedUrl,
                        size: parseInt((await file.getMetadata())[0].size || 0)
                    }
                }))
                
                console.log(`Returning ${filesWithUrls.length} signed URLs for client-side ZIP`)
                res.status(200).json({
                    mode: 'clientZip', // Tell client to ZIP these files
                    files: filesWithUrls,
                    totalFiles: filesWithUrls.length,
                    totalSizeMB: estimatedSizeMB
                })
                return
            }
            
            console.log(`Size ${estimatedSizeMB}MB under ${SERVER_ZIP_THRESHOLD_MB}MB threshold - creating server-side ZIP`)
            
            // Create job document for server-side ZIP
            await jobDocRef.set({
                status: 'processing',
                progress: 0,
                message: 'Starting ZIP creation...',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                createdBy: uid,
                fileCount: mp4Files.length,
                estimatedSizeMB: estimatedSizeMB,
                eventId: event.id
            })

            // Return immediately with job info - client will poll for updates
            res.status(202).json({
                jobId: event.id,
                status: 'processing',
                progress: 5,
                message: 'ZIP creation started...',
                fileCount: mp4Files.length,
                estimatedSizeMB: estimatedSizeMB,
                estimatedTimeSeconds: Math.ceil(mp4Files.length * 0.5) // Rough estimate: 0.5 sec per file
            })

            // Start ZIP creation AFTER sending response
            console.log(`Starting ZIP creation for event ${event.id} with ${mp4Files.length} files`)
            
            // Keep the function alive by awaiting the work
            await createZipFile(event.id, mp4Files, jobDocRef).catch(err => {
                console.error('Error in ZIP creation:', err)
                return jobDocRef.update({
                    status: 'failed',
                    error: err.message,
                    completedAt: admin.firestore.FieldValue.serverTimestamp()
                }).catch(e => console.error('Failed to update error status:', e))
            })

        } catch (err) {
            console.error('Error processing request:', err)
            if (!res.headersSent) {
                res.status(500).json({ error: 'Internal Server Error', details: err.message })
            }
        }
    })
})

// Background function to create ZIP file
async function createZipFile(eventId, files, jobDocRef) {
    const bucket = storage.bucket(bucketName)
    const zipFileName = `${eventId}/recordings_${Date.now()}.zip`
    const zipFile = bucket.file(zipFileName)
    
    console.log(`[ZIP ${eventId}] Starting ZIP creation with ${files.length} files`)
    console.log(`[ZIP ${eventId}] Bucket: ${bucketName}, ZIP path: ${zipFileName}`)
    
    try {
        await jobDocRef.update({
            progress: 5,
            message: `Processing ${files.length} files...`
        })
        console.log(`[ZIP ${eventId}] Updated job progress to 5%`)
    } catch (err) {
        console.error(`[ZIP ${eventId}] Failed to update progress:`, err)
    }

    const writeStream = zipFile.createWriteStream({
        metadata: {
            contentType: 'application/zip',
            metadata: {
                eventId: eventId,
                createdAt: new Date().toISOString()
            }
        },
        resumable: true, // Resumable upload uses parallel chunks - faster for large files
        chunkSize: 5 * 1024 * 1024, // 5MB chunks
    })

    const archive = archiver('zip', {
        store: true, // No compression - just package files (10-100x faster)
    })

    let errorOccurred = false
    let uploadedBytes = 0

    archive.on('error', async (err) => {
        console.error(`[ZIP ${eventId}] Archive error:`, err)
        errorOccurred = true
        await jobDocRef.update({
            status: 'failed',
            error: err.message,
            completedAt: admin.firestore.FieldValue.serverTimestamp()
        }).catch(e => console.error(`[ZIP ${eventId}] Failed to update job status:`, e))
    })

    // Track upload progress
    writeStream.on('progress', (progress) => {
        console.log(`[ZIP ${eventId}] Upload progress:`, progress)
    })

    // Pipe the archive to Cloud Storage
    archive.pipe(writeStream)

    console.log(`Starting to add ${files.length} files to archive`)

    // Add all files to archive
    for (let i = 0; i < files.length; i++) {
        const file = files[i]
        
        try {
            const fileStream = file.createReadStream()
            const entryName = file.name.split('/').pop() // Use just the filename
            archive.append(fileStream, { name: entryName })
            
            // Update progress every 20 files (non-blocking)
            if (i > 0 && (i % 20 === 0 || i === files.length - 1)) {
                const percentComplete = Math.round((i / files.length) * 85) + 10
                console.log(`Progress: ${percentComplete}% (${i}/${files.length} files)`)
                // Don't await - let it update in background
                jobDocRef.update({
                    progress: percentComplete,
                    message: `Adding files to ZIP: ${i}/${files.length}...`
                }).catch(e => console.error('Failed to update progress:', e))
            }
        } catch (fileErr) {
            console.error(`Error adding file ${file.name}:`, fileErr)
            // Continue with other files
        }
    }

    console.log(`[ZIP ${eventId}] Finalizing archive...`)
    await jobDocRef.update({
        progress: 95,
        message: 'Finalizing ZIP file...'
    }).catch(e => console.error(`[ZIP ${eventId}] Failed to update progress:`, e))

    await archive.finalize()
    console.log(`[ZIP ${eventId}] Archive finalized, waiting for upload to complete...`)

    await jobDocRef.update({
        progress: 96,
        message: 'Uploading ZIP to storage...'
    }).catch(e => console.error(`[ZIP ${eventId}] Failed to update progress:`, e))

    // Wait for the write stream to finish with timeout
    const uploadTimeout = 480000 // 8 minutes
    await Promise.race([
        new Promise((resolve, reject) => {
            writeStream.on('finish', () => {
                console.log(`[ZIP ${eventId}] writeStream finished successfully`)
                resolve()
            })
            writeStream.on('error', (err) => {
                console.error(`[ZIP ${eventId}] writeStream error:`, err)
                reject(err)
            })
        }),
        new Promise((_, reject) => 
            setTimeout(() => reject(new Error('Upload timeout after 8 minutes')), uploadTimeout)
        )
    ]).catch(err => {
        console.error(`[ZIP ${eventId}] Error waiting for upload:`, err)
        throw err
    })

    if (errorOccurred) {
        console.error(`[ZIP ${eventId}] Error occurred during ZIP creation, aborting`)
        return
    }

    console.log(`[ZIP ${eventId}] Upload completed successfully`)

    // Generate signed URL (valid for 7 days)
    const [signedUrl] = await zipFile.getSignedUrl({
        action: 'read',
        expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
    })

    // Get final file size
    const [metadata] = await zipFile.getMetadata()
    const finalSizeMB = Math.round(parseInt(metadata.size) / (1024 * 1024))

    // Update job as completed
    await jobDocRef.update({
        status: 'completed',
        progress: 100,
        message: 'ZIP file ready for download',
        downloadUrl: signedUrl,
        zipFilePath: zipFileName,
        finalSizeMB: finalSizeMB,
        completedAt: admin.firestore.FieldValue.serverTimestamp()
    })

    console.log(`ZIP download URL generated for event ${eventId}`)
}

module.exports = downloadRecording
