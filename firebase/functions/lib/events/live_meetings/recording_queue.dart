import 'dart:async';
import 'dart:math';
import 'agora_api.dart';

/// A queue system for starting recordings with rate limiting and retry logic.
/// 
/// Designed to handle up to 2,500 concurrent breakout rooms without hitting
/// Agora API rate limits (~500 requests/second for Pro tier).
/// 
/// Features:
/// - Batch processing with controlled concurrency
/// - Exponential backoff on rate limit errors (429)
/// - Retry logic for transient failures
/// - Progress tracking and logging
class RecordingQueue {
  /// Maximum number of recordings to start simultaneously
  /// 100 concurrent = ~200 API calls/sec (acquire + start)
  /// Leaves headroom for other API operations
  static const int maxConcurrentRecordings = 100;
  
  /// Delay between batches to avoid sustained rate limit hits
  static const Duration batchDelay = Duration(milliseconds: 200);
  
  /// Maximum retry attempts for failed recordings
  static const int maxRetries = 3;
  
  /// Base delay for exponential backoff (increases with each retry)
  static const Duration baseRetryDelay = Duration(seconds: 1);
  
  final AgoraUtils _agoraUtils = AgoraUtils();
  final List<_RecordingTask> _queue = [];
  final Set<String> _processing = {};
  bool _isProcessing = false;
  
  /// Singleton instance
  static final RecordingQueue _instance = RecordingQueue._internal();
  factory RecordingQueue() => _instance;
  RecordingQueue._internal();
  
  /// Queues a recording to be started with rate limiting and retry logic.
  /// 
  /// Returns a Future that completes when the recording has successfully started
  /// or has exhausted all retry attempts.
  /// 
  /// Deduplicates at entry: if the same roomId is already queued or processing,
  /// this returns immediately without adding a duplicate task.
  Future<void> queueRecording({
    required String roomId,
    String? eventId,
    String? filePrefix,
    String? recordingStatePath,
    String? screenSharerUserId,
    int? screenShareAgoraUid,
  }) async {
    // Check if this room is already queued or being processed
    final isAlreadyQueued = _queue.any((task) => task.roomId == roomId);
    final isAlreadyProcessing = _processing.contains(roomId);
    
    if (isAlreadyQueued || isAlreadyProcessing) {
      print('[RecordingQueue] Room $roomId already queued or processing, skipping duplicate');
      return; // Already queued or processing, don't add duplicate
    }
    
    final task = _RecordingTask(
      roomId: roomId,
      eventId: eventId,
      filePrefix: filePrefix,
      recordingStatePath: recordingStatePath,
      screenSharerUserId: screenSharerUserId,
      screenShareAgoraUid: screenShareAgoraUid,
      completer: Completer<void>(),
    );
    
    _queue.add(task);
    print('[RecordingQueue] Queued recording for room $roomId (queue size: ${_queue.length})');
    
    // Start processing if not already running
    if (!_isProcessing) {
      unawaited(_processQueue());
    }
    
    return task.completer.future;
  }
  
  /// Processes the queue in batches with rate limiting
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    
    print('[RecordingQueue] Starting queue processing (${_queue.length} tasks)');
    
    try {
      // Outer loop: concurrent GetBreakoutRoomJoinInfo calls can enqueue tasks
      // after an inner drain thinks the queue is empty but before _isProcessing
      // is cleared. A yield lets those callbacks run; we only exit when the queue
      // stays empty after yielding (avoids stranded tasks and silent no-ops).
      do {
        while (_queue.isNotEmpty) {
          final batchSize = min(maxConcurrentRecordings, _queue.length);
          final batch = _queue.take(batchSize).toList();
          _queue.removeRange(0, batchSize);

          print('[RecordingQueue] Processing batch of $batchSize recordings (${_queue.length} remaining)');

          await Future.wait(
            batch.map((task) => _processTask(task)),
          );

          if (_queue.isNotEmpty) {
            await Future.delayed(batchDelay);
          }
        }
        await Future<void>.delayed(Duration.zero);
      } while (_queue.isNotEmpty);

      print('[RecordingQueue] Queue processing complete');
    } catch (e, stackTrace) {
      print('[RecordingQueue] Error processing queue: $e');
      print('Stack trace: $stackTrace');
    } finally {
      _isProcessing = false;
      // Stranded work can remain after a batch error (catch above) or rare races.
      // Restart is intentional on that path too; _processQueue's synchronous
      // `if (_isProcessing) return` avoids double-run now that the flag is false.
      if (_queue.isNotEmpty) {
        unawaited(_processQueue());
      }
    }
  }
  
  /// Processes a single recording task with retry logic
  Future<void> _processTask(_RecordingTask task) async {
    final roomId = task.roomId;
    
    if (_processing.contains(roomId)) {
      print('[RecordingQueue] Room $roomId already being processed, skipping');
      task.completer.complete();
      return;
    }
    
    _processing.add(roomId);
    
    try {
      await _startRecordingWithRetry(task);
      task.completer.complete();
    } catch (e) {
      print('[RecordingQueue] Failed to start recording for room $roomId after ${task.attempts} attempts: $e');
      task.completer.completeError(e);
    } finally {
      _processing.remove(roomId);
    }
  }
  
  /// Attempts to start a recording with exponential backoff retry
  Future<void> _startRecordingWithRetry(_RecordingTask task) async {
    while (task.attempts < maxRetries) {
      task.attempts++;
      
      try {
        await _agoraUtils.recordRoom(
          roomId: task.roomId,
          eventId: task.eventId,
          filePrefix: task.filePrefix,
          recordingStatePath: task.recordingStatePath,
          screenSharerUserId: task.screenSharerUserId,
          screenShareAgoraUid: task.screenShareAgoraUid,
        );
        
        print('[RecordingQueue] Successfully started recording for room ${task.roomId} (attempt ${task.attempts})');
        return; // Success!
        
      } catch (e) {
        final isRateLimitError = e.toString().contains('429') || 
                                  e.toString().contains('rate limit') ||
                                  e.toString().contains('Too Many Requests');
        
        final isLastAttempt = task.attempts >= maxRetries;
        
        if (isLastAttempt) {
          print('[RecordingQueue] Room ${task.roomId} failed after ${task.attempts} attempts: $e');
          rethrow;
        }
        
        // Calculate backoff delay (exponential with jitter)
        final backoffSeconds = baseRetryDelay.inSeconds * pow(2, task.attempts - 1);
        final jitter = Random().nextInt(1000); // 0-999ms jitter
        final delay = Duration(seconds: backoffSeconds.toInt(), milliseconds: jitter);
        
        final errorType = isRateLimitError ? 'Rate limit' : 'Error';
        print('[RecordingQueue] $errorType for room ${task.roomId} (attempt ${task.attempts}/$maxRetries), retrying in ${delay.inSeconds}s: $e');
        
        await Future.delayed(delay);
      }
    }
  }
  
  /// Returns current queue stats for monitoring
  Map<String, dynamic> getStats() {
    return {
      'queueSize': _queue.length,
      'processing': _processing.length,
      'isProcessing': _isProcessing,
    };
  }
}

/// Internal class representing a recording task in the queue
class _RecordingTask {
  final String roomId;
  final String? eventId;
  final String? filePrefix;
  final String? recordingStatePath;
  final String? screenSharerUserId;
  final int? screenShareAgoraUid;
  final Completer<void> completer;
  int attempts = 0;
  
  _RecordingTask({
    required this.roomId,
    this.eventId,
    this.filePrefix,
    this.recordingStatePath,
    this.screenSharerUserId,
    this.screenShareAgoraUid,
    required this.completer,
  });
}

