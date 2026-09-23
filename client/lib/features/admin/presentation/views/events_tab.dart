import 'dart:async';
import 'dart:convert';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/empty_page_content.dart';
import 'package:client/core/widgets/custom_list_view.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/config/environment.dart';
import 'package:client/core/routing/locations.dart';

import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:data_models/events/event.dart';
import 'package:universal_html/html.dart' as html;

enum _RecordingCheckState {
  checking,
  available,
  none,
  failed,
  /// Firestore DB used by Cloud Functions does not contain the event (e.g. wrong FIREBASE_DATABASE_ID).
  eventNotFound,
}


class EventsTab extends StatefulWidget {
  @override
  _EventsTabState createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  final _participantCountFutures = <String, Future<List<Participant>>>{};

  late BehaviorSubjectWrapper<List<Event>> _allEvents;

  var _numToShow = 10;
  bool _isDownloadingRecordings = false;
  final Map<String, bool> _isDownloadingTranscription = {};

  final Map<String, _RecordingCheckState> _recordingAvailability = {};
  final Set<String> _recordingCheckScheduled = {};

  final Map<String, _RecordingCheckState> _transcriptionAvailability = {};
  final Set<String> _transcriptionCheckScheduled = {};

  @override
  void initState() {
    super.initState();

    _allEvents = firestoreEventService.communityEvents(
      communityId: CommunityProvider.read(context).communityId,
    );
  }

  @override
  void dispose() {
    _allEvents.dispose();
    super.dispose();
  }

  Widget _buildRowEntry({double? width, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      width: width,
      child: child,
    );
  }

  Widget _buildEventHeaders({required bool showDetails}) {
    return Row(
      children: [
        _buildRowEntry(
          width: 200,
          child: Text(
            'Date',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        _buildRowEntry(
          width: 320,
          child: Text(
            'Title',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (showDetails)
          _buildRowEntry(
            width: 70,
            child: Text(
              'Visibility',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (showDetails)
          _buildRowEntry(
            width: 80,
            child: Text(
              'Status',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (showDetails)
          _buildRowEntry(
            width: 100,
            child: Text(
              'Participants',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        _buildRowEntry(
          width: 170,
          child: Text(
            'Recordings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        _buildRowEntry(
          width: 180,
          child: Text(
            'Transcriptions',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  ButtonStyle get _compactRecordingButtonStyle => TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  Widget _buildRecordingSection(Event event, {required int index}) {
    final hasRecording = event.eventSettings?.alwaysRecord ?? false;
    final hasEnded = event.isEnded || event.isLocked;

    if (!hasRecording || !hasEnded) return const Text('');

    if (!_recordingCheckScheduled.contains(event.id)) {
      _recordingCheckScheduled.add(event.id);
      // Stagger checks by 500ms per row so all events don't hit the Cloud
      // Function simultaneously (maxInstances: 10 + 30s timeout → failures).
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Future.delayed(
          Duration(milliseconds: index * 1000),
          () => _checkRecordingAvailability(event),
        // Silence the unawaited future: any escaped error would reach FlutterFire's
        // zone handler on web and throw a spurious TypeError (TimeoutException is not
        // a JavaScriptObject). Errors are already handled inside _checkRecordingAvailability.
        ).catchError((_, __) {}),
      );
    }

    final availability = _recordingAvailability[event.id];
    if (availability == null || availability == _RecordingCheckState.checking) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: 'Checking recording availability',
        ),
      );
    }

    if (availability == _RecordingCheckState.failed) {
      return TextButton(
        style: _compactRecordingButtonStyle,
        onPressed: () => _checkRecordingAvailability(event),
        child: const Text('Retry'),
      );
    }

    if (availability == _RecordingCheckState.eventNotFound) {
      return Tooltip(
        message:
            'Cloud Functions returned EVENT_NOT_FOUND: the event document is missing '
            'in the Firestore database the functions use. Set app.firebase_database_id '
            '(or FIREBASE_DATABASE_ID at deploy) to match this app.',
        child: TextButton(
          style: _compactRecordingButtonStyle,
          onPressed: () => _checkRecordingAvailability(event),
          child: const Text('DB config'),
        ),
      );
    }

    if (availability == _RecordingCheckState.none) {
      return Tooltip(
        message:
            'No recording file in storage yet. Use Recheck if the event '
            'just ended and upload may still be finishing.',
        child: TextButton(
          style: _compactRecordingButtonStyle,
          onPressed: () => _checkRecordingAvailability(event),
          child: const Text('Recheck'),
        ),
      );
    }

    // available
    return ActionButton(
      type: ActionButtonType.outline,
      loadingHeight: 16,
      borderSide: BorderSide(
        color: _isDownloadingRecordings
            ? AppNeutralColors.of(context).neutral400
            : Theme.of(context).colorScheme.primary,
      ),
      textColor: _isDownloadingRecordings
          ? AppNeutralColors.of(context).neutral400
          : Theme.of(context).colorScheme.primary,
      onPressed:
          _isDownloadingRecordings ? null : () => _downloadRecordings(event),
      text: _isDownloadingRecordings ? 'Downloading...' : 'Download',
    );
  }

  Future<void> _checkRecordingAvailability(Event event) async {
    if (mounted) {
      setState(() => _recordingAvailability[event.id] = _RecordingCheckState.checking);
    }

    try {
      final idToken =
          await userService.firebaseAuth.currentUser?.getIdToken();
      final response = await http
          .post(
            Uri.parse(
              '${Environment.functionsUrlPrefix}/downloadRecording',
            ),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'eventPath': event.fullPath,
              'checkOnly': true,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _recordingAvailability[event.id] = _RecordingCheckState.available);
      } else if (response.statusCode == 404) {
        String? errorCode;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            errorCode = decoded['code'] as String?;
          }
        } catch (_) {}
        setState(
          () => _recordingAvailability[event.id] =
              errorCode == 'EVENT_NOT_FOUND'
                  ? _RecordingCheckState.eventNotFound
                  : _RecordingCheckState.none,
        );
      } else {
        setState(() => _recordingAvailability[event.id] = _RecordingCheckState.failed);
      }
    } on TimeoutException catch (_) {
      // Caught explicitly so TimeoutException doesn't propagate through
      // FlutterFire's zone handler on web (causes spurious TypeError).
      if (mounted) {
        setState(() => _recordingAvailability[event.id] = _RecordingCheckState.failed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recordingAvailability[event.id] = _RecordingCheckState.failed);
      }
    }
  }

  Future<void> _downloadRecordings(Event event) async {
    if (_isDownloadingRecordings) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Download already in progress. Please wait for it to complete.',
          ),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isDownloadingRecordings = true);
    ScaffoldMessenger.of(context).clearSnackBars();

    try {
      await alertOnError(
        context,
        () async {
          final idToken =
              await userService.firebaseAuth.currentUser?.getIdToken();
          final response = await http.post(
            Uri.parse('${Environment.functionsUrlPrefix}/downloadRecording'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'eventPath': event.fullPath}),
          );

          dynamic data;
          try {
            data = jsonDecode(response.body);
          } catch (_) {
            data = null;
          }

          if (response.statusCode == 404) {
            String msg = 'Recording download failed (404).';
            if (data is Map && data['error'] != null) {
              final code = data['code'] as String?;
              msg = '${data['error']}${code != null ? ' [$code]' : ''}';
              if (code == 'EVENT_NOT_FOUND') {
                msg += ' If events use a named Firestore database, set app.firebase_database_id (or FIREBASE_DATABASE_ID) on Cloud Functions.';
              }
            }
            throw Exception(msg);
          }

          if (response.statusCode != 200) {
            ScaffoldMessenger.of(context).clearSnackBars();
            var msg = 'Failed to get recording files: ${response.statusCode}';
            try {
              final errBody = jsonDecode(response.body);
              if (errBody is Map && errBody['error'] != null) {
                msg =
                    '${errBody['error']} (${errBody['code'] ?? response.statusCode})';
              }
            } catch (_) {}
            throw Exception(msg);
          }

          if (data is! Map<String, dynamic>) {
            throw Exception('Invalid download response');
          }
          final map = data;
          final files = map['files'] as List?;
          if (files == null || files.isEmpty) {
            throw Exception('Invalid download response: no files');
          }
          if ((map['mode'] as String?) != 'individual') {
            throw Exception(
              'Recording download requires an updated downloadRecording function '
              '(expected mode "individual").',
            );
          }

          final filesList = files.cast<Map<String, dynamic>>();
          final totalFiles = map['totalFiles'] as int? ?? filesList.length;
          final totalSizeMB = map['totalSizeMB'] as int? ?? 0;
          final message = map['message'] as String?;

          ScaffoldMessenger.of(context).clearSnackBars();

          final sizeGB = (totalSizeMB / 1024).toStringAsFixed(1);
          final estimatedMinutes = (totalFiles * 5 / 60).ceil();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message ??
                    'Starting sequential download of $totalFiles files (${sizeGB}GB total). '
                    'This will take approximately $estimatedMinutes minutes. '
                    'DO NOT close this tab during download!',
              ),
              duration: Duration(seconds: 10),
              backgroundColor: Colors.blue[700],
            ),
          );

          await Future.delayed(Duration(seconds: 3));

          await _downloadFilesSequentially(
            filesList,
            totalFiles,
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloadingRecordings = false);
      }
    }
  }

  /// Downloads files sequentially with proper delays to handle large-scale downloads
  /// This method ensures all files download even in extreme cases (2500+ files)
  Future<void> _downloadFilesSequentially(
    List<Map<String, dynamic>> filesList,
    int totalFiles,
  ) async {
    const delayBetweenDownloads = Duration(seconds: 5);
    int successCount = 0;
    int failureCount = 0;
    
    for (var i = 0; i < filesList.length; i++) {
      try {
        final fileData = filesList[i];
        final url = fileData['url'] as String;
        final name = fileData['name'] as String;
        final fileSizeMB = ((fileData['size'] as int?) ?? 0) / (1024 * 1024);
        
        // Update progress BEFORE starting download
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Starting download ${i + 1} of $totalFiles: $name '
              '(${fileSizeMB.toStringAsFixed(1)}MB)... '
              'Success: $successCount, Failed: $failureCount'
            ),
            duration: Duration(seconds: 7), // Show for duration of delay
          ),
        );
        
        // Use proper download method with anchor element
        // This is more reliable than window.open() and respects browser download settings
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', name)
          ..setAttribute('target', '_blank')
          ..style.display = 'none';
        
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
        
        successCount++;
        
        // Wait before starting next download
        // This prevents browser queue overflow and gives each download time to initialize
        // Critical for large files (900MB+) and large quantities (2500+)
        if (i < filesList.length - 1) {
          await Future.delayed(delayBetweenDownloads);
        }
        
      } catch (e) {
        print('Error downloading file ${i + 1}: $e');
        failureCount++;
        
        // Show error but continue with remaining files
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download file ${i + 1}. Continuing with remaining files...'),
            duration: Duration(seconds: 3),
          ),
        );
        
        // Brief delay before continuing
        await Future.delayed(Duration(seconds: 2));
      }
    }
    
    // Show final summary
    ScaffoldMessenger.of(context).clearSnackBars();
    
    if (failureCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully started all $totalFiles downloads! '
            'Check your downloads folder and browser download manager.'
          ),
          duration: Duration(seconds: 8),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloads complete: $successCount succeeded, $failureCount failed. '
            'You may need to retry failed downloads.'
          ),
          duration: Duration(seconds: 10),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildTranscriptionSection(Event event, {required int index}) {
    final hasTranscription = event.eventSettings?.alwaysTranscribe ?? false;
    final hasEnded = event.isEnded || event.isLocked;

    if (!hasTranscription || !hasEnded) return const Text('');

    if (!_transcriptionCheckScheduled.contains(event.id)) {
      _transcriptionCheckScheduled.add(event.id);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Future.delayed(
          // Offset by 500ms from the recording check (which uses index * 1000ms)
          // so the two checkOnly requests per event interleave rather than burst
          // simultaneously — keeps peak concurrency within maxInstances:10.
          Duration(milliseconds: index * 1000 + 500),
          () => _checkTranscriptionAvailability(event),
        ).catchError((_, __) {}),
      );
    }

    final availability = _transcriptionAvailability[event.id];
    if (availability == null || availability == _RecordingCheckState.checking) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: 'Checking transcription availability',
        ),
      );
    }

    if (availability == _RecordingCheckState.failed) {
      return TextButton(
        style: _compactRecordingButtonStyle,
        onPressed: () => _checkTranscriptionAvailability(event),
        child: const Text('Retry'),
      );
    }

    if (availability == _RecordingCheckState.eventNotFound) {
      return Tooltip(
        message: 'Event not found in Cloud Functions Firestore database.',
        child: TextButton(
          style: _compactRecordingButtonStyle,
          onPressed: () => _checkTranscriptionAvailability(event),
          child: const Text('DB config'),
        ),
      );
    }

    if (availability == _RecordingCheckState.none) {
      return Tooltip(
        message: 'No transcription files yet. Use Recheck if the event just ended.',
        child: TextButton(
          style: _compactRecordingButtonStyle,
          onPressed: () => _checkTranscriptionAvailability(event),
          child: const Text('Recheck'),
        ),
      );
    }

    final isDownloading = _isDownloadingTranscription[event.id] ?? false;
    return ActionButton(
      type: ActionButtonType.outline,
      loadingHeight: 16,
      borderSide: BorderSide(
        color: isDownloading
            ? AppNeutralColors.of(context).neutral400
            : Theme.of(context).colorScheme.primary,
      ),
      textColor: isDownloading
          ? AppNeutralColors.of(context).neutral400
          : Theme.of(context).colorScheme.primary,
      onPressed: isDownloading ? null : () => _downloadTranscription(event),
      text: isDownloading ? 'Zipping...' : 'Download ZIP',
    );
  }

  Future<void> _checkTranscriptionAvailability(Event event) async {
    if (mounted) {
      setState(
        () => _transcriptionAvailability[event.id] = _RecordingCheckState.checking,
      );
    }

    try {
      final idToken = await userService.firebaseAuth.currentUser?.getIdToken();
      final response = await http
          .post(
            Uri.parse('${Environment.functionsUrlPrefix}/downloadTranscription'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'eventPath': event.fullPath,
              'checkOnly': true,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(
          () => _transcriptionAvailability[event.id] = _RecordingCheckState.available,
        );
      } else if (response.statusCode == 404) {
        String? errorCode;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) errorCode = decoded['code'] as String?;
        } catch (_) {}
        setState(
          () => _transcriptionAvailability[event.id] =
              errorCode == 'EVENT_NOT_FOUND'
                  ? _RecordingCheckState.eventNotFound
                  : _RecordingCheckState.none,
        );
      } else {
        setState(
          () => _transcriptionAvailability[event.id] = _RecordingCheckState.failed,
        );
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(
          () => _transcriptionAvailability[event.id] = _RecordingCheckState.failed,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _transcriptionAvailability[event.id] = _RecordingCheckState.failed,
        );
      }
    }
  }

  Future<void> _downloadTranscription(Event event) async {
    if (_isDownloadingTranscription[event.id] ?? false) return;
    if (!mounted) return;
    setState(() => _isDownloadingTranscription[event.id] = true);
    ScaffoldMessenger.of(context).clearSnackBars();

    try {
      await alertOnError(context, () async {
        final idToken = await userService.firebaseAuth.currentUser?.getIdToken();
        final response = await http
            .post(
              Uri.parse(
                '${Environment.functionsUrlPrefix}/downloadTranscription',
              ),
              headers: {
                'Authorization': 'Bearer $idToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'eventPath': event.fullPath}),
            )
            .timeout(const Duration(minutes: 7));

        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          data = null;
        }

        if (response.statusCode == 404) {
          String msg = 'Transcription download failed (404).';
          if (data is Map && data['error'] != null) {
            msg = data['error'] as String;
          }
          throw Exception(msg);
        }

        if (response.statusCode != 200) {
          String msg = 'Failed to get transcription files: ${response.statusCode}';
          if (data is Map && data['error'] != null) {
            msg = data['error'] as String;
          }
          throw Exception(msg);
        }

        if (data is! Map<String, dynamic>) {
          throw Exception('Invalid transcription download response');
        }

        final url = data['url'] as String?;
        final fileName = data['fileName'] as String? ?? 'transcriptions.zip';
        final fileCount = data['fileCount'] as int? ?? 0;
        final message = data['message'] as String?;

        if (url == null) throw Exception('No download URL in response');

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message ??
                  'Transcription ZIP ready ($fileCount file(s)). Starting download...',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.blue[700],
          ),
        );

        await Future.delayed(const Duration(seconds: 2));

        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..setAttribute('target', '_blank')
          ..style.display = 'none';
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription ZIP download started: $fileName'),
            duration: const Duration(seconds: 6),
            backgroundColor: Colors.green,
          ),
        );
      });
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Transcription ZIP timed out. The event may have many rooms — '
              'please try again.',
            ),
            duration: Duration(seconds: 8),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingTranscription[event.id] = false);
    }
  }

  String _eventLiveStatus(Event event) {
    if (event.isEnded || event.isLocked) return 'Ended';
    final scheduled = event.scheduledTime;
    if (scheduled == null) return '—';
    final now = clockService.now();
    if (scheduled.isAfter(now)) return 'Upcoming';
    return 'Live';
  }

  Future<List<Participant>> _participantCountFuture(Event event) {
    return _participantCountFutures.putIfAbsent(
      event.fullPath,
      () => firestoreEventService.getEventParticipants(event: event),
    );
  }

  String _participantCountText(Event event) {
    final count =
        event.participantCountEstimate ?? event.presentParticipantCountEstimate;
    return count != null ? count.toString() : '—';
  }

  Widget _buildParticipantCountCell(Event event) {
    return FutureBuilder<List<Participant>>(
      future: _participantCountFuture(event),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final activeParticipantCount = snapshot.data!
              .where(
                (participant) => participant.status == ParticipantStatus.active,
              )
              .length;

          return HeightConstrainedText(activeParticipantCount.toString());
        }

        if (snapshot.hasError) {
          return Tooltip(
            message: 'Could not load participant count.',
            child: HeightConstrainedText(_participantCountText(event)),
          );
        }

        return HeightConstrainedText(_participantCountText(event));
      },
    );
  }

  Widget _buildEventRow({
    required int index,
    required Event event,
    required bool showDetails,
  }) {
    final timeFormat = DateFormat('MMM d yyyy, h:mma');
    final timezone = getTimezoneAbbreviation(event.scheduledTime!);
    final time = timeFormat.format(event.scheduledTime ?? clockService.now());

    return Container(
      color: index.isEven
          ? context.theme.colorScheme.primary.withOpacity(0.1)
          : Colors.white70,
      child: Row(
        children: [
          _buildRowEntry(
            width: 200,
            child: GestureDetector(
              onTap: () => routerDelegate.beamTo(
                CommunityPageRoutes(
                  communityDisplayId: CommunityProvider.read(context).displayId,
                ).eventPage(
                  templateId: event.templateId,
                  eventId: event.id,
                  eventTitle: event.title,
                ),
              ),
              child: HeightConstrainedText(
                '$time $timezone',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          _buildRowEntry(
            width: 320,
            child: HeightConstrainedText(event.title ?? event.id),
          ),
          if (showDetails)
            _buildRowEntry(
              width: 70,
              child: HeightConstrainedText(
                event.isPublic == true ? 'Public' : 'Private',
              ),
            ),
          if (showDetails)
            _buildRowEntry(
              width: 80,
              child: HeightConstrainedText(_eventLiveStatus(event)),
            ),
          if (showDetails)
            _buildRowEntry(
              width: 100,
              child: _buildParticipantCountCell(event),
            ),
          _buildRowEntry(
            width: 170,
            child: SizedBox(
              width: 170,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _buildRecordingSection(event, index: index),
                ),
              ),
            ),
          ),
          _buildRowEntry(
            width: 180,
            child: SizedBox(
              width: 180,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _buildTranscriptionSection(event, index: index),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList({
    required List<Event> events,
    required bool showDetails,
  }) {
    return CustomListView(
      children: [
        for (int i = 0; i < events.length; i++)
          FittedBox(
            fit: BoxFit.fitWidth,
            child: _buildEventRow(
              index: i,
              event: events[i],
              showDetails: showDetails,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool showDetails = !responsiveLayoutService.isMobile(context);
    return CustomStreamBuilder<List<Event>>(
      stream: _allEvents.stream,
      entryFrom: '_EventsTabState.build',
      builder: (_, events) {
        if (events == null || events.isEmpty) {
          return EmptyPageContent(
            type: EmptyPageType.events,
            showContainer: false,
          );
        }

        return CustomListView(
          children: [
            FittedBox(
              fit: BoxFit.fitWidth,
              child: _buildEventHeaders(showDetails: showDetails),
            ),
            _buildEventsList(
              events: events.take(_numToShow).toList(),
              showDetails: showDetails,
            ),
            if (_numToShow < events.length)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: ActionButton(
                  onPressed: () => setState(() => _numToShow += 10),
                  text: 'View more',
                ),
              ),
          ],
        );
      },
    );
  }
}
