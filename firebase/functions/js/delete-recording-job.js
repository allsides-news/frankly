// Temporary function to delete a stuck recording job
const functions = require('firebase-functions')
const admin = require('firebase-admin')
const cors = require('cors')({ origin: true })

const deleteRecordingJob = functions.https.onRequest((req, res) => {
    cors(req, res, async () => {
        const eventId = req.query.eventId || req.body.eventId
        
        if (!eventId) {
            res.status(400).send('eventId required')
            return
        }

        try {
            await admin.firestore().collection('recordingJobs').doc(eventId).delete()
            res.status(200).json({ message: `Deleted recording job for ${eventId}` })
        } catch (err) {
            console.error('Error deleting job:', err)
            res.status(500).json({ error: err.message })
        }
    })
})

module.exports = deleteRecordingJob

