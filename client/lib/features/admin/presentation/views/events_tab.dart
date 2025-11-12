import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:data_models/events/event.dart';
import 'package:universal_html/html.dart' as html;

class EventsTab extends StatefulWidget {
  @override
  _EventsTabState createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  late BehaviorSubjectWrapper<List<Event>> _allEvents;

  var _numToShow = 10;
  bool _isDownloadingRecordings = false;

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
              'Live?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (showDetails)
          _buildRowEntry(
            width: 100,
            child: Text(
              'Num Participants',
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
      ],
    );
  }

  Widget _buildRecordingSection(Event event) {
    // Only show download button if:
    // 1. Recording is enabled
    // 2. Event has ended (isLocked = true)
    final hasRecording = event.eventSettings?.alwaysRecord ?? false;
    final hasEnded = event.isLocked;
    
    if (!hasRecording || !hasEnded) {
      return Text('');
    } else {
      return ActionButton(
        type: ActionButtonType.outline,
        loadingHeight: 16,
        borderSide: BorderSide(
          color: _isDownloadingRecordings 
            ? Colors.grey 
            : Theme.of(context).primaryColor
        ),
        textColor: _isDownloadingRecordings 
          ? Colors.grey 
          : Theme.of(context).primaryColor,
        onPressed: _isDownloadingRecordings 
          ? null 
          : () => _downloadRecordings(event),
        text: _isDownloadingRecordings ? 'Downloading...' : 'Download',
      );
    }
  }

  Future<void> _downloadRecordings(Event event) async {
    // Clear ALL existing snackbars at the start
    ScaffoldMessenger.of(context).clearSnackBars();
    
    await alertOnError(
      context,
      () async {
        final idToken = await userService.firebaseAuth.currentUser?.getIdToken();
        final response = await http.post(
          Uri.parse('${Environment.functionsUrlPrefix}/downloadRecording'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'eventPath': event.fullPath}),
        );

        final data = jsonDecode(response.body);
        
        if (response.statusCode == 202) {
          // ZIP is being created in background - poll for completion
          final jobId = data['jobId'] as String;
          final message = data['message'] as String? ?? 'Creating ZIP file...';
          final estimatedTimeSec = data['estimatedTimeSeconds'] as int? ?? 30;
          
          // Show initial message - will stay visible during polling
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$message ~$estimatedTimeSec seconds...'),
              duration: Duration(seconds: estimatedTimeSec * 2), // Long duration
            ),
          );
          
          // Poll for job completion
          final downloadUrl = await _pollForZipCompletion(jobId, estimatedTimeSec);
          
          // Clear progress message
          ScaffoldMessenger.of(context).clearSnackBars();
          
          if (downloadUrl != null) {
            // Download the ZIP file
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Downloading ZIP file...'),
                duration: Duration(seconds: 2),
              ),
            );
            
            html.window.open(downloadUrl, '_blank');
            
            // Wait a moment then show success
            await Future.delayed(Duration(milliseconds: 500));
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Recording downloaded successfully!'),
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            throw Exception('ZIP creation timed out or failed');
          }
          
          return;
        }
        
        if (response.statusCode == 200) {
          // Check what type of 200 response this is
          final status = data['status'] as String?;
          final downloadUrl = data['downloadUrl'] as String?;
          final files = data['files'] as List?;
          
          // Case 1: Job already completed - has downloadUrl
          if (downloadUrl != null) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Downloading ZIP file...')),
            );
            html.window.open(downloadUrl, '_blank');
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Recording downloaded successfully!'),
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }
          
          // Case 2: Job still processing - poll for completion
          if (status == 'processing') {
            final jobId = data['jobId'] as String;
            final message = data['message'] as String? ?? 'Creating ZIP file...';
            final progress = data['progress'] as int? ?? 0;
            
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$message $progress%...')),
            );
            
            final completedUrl = await _pollForZipCompletion(jobId, 60);
            if (completedUrl != null) {
              html.window.open(completedUrl, '_blank');
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recording downloaded successfully!'),
                  duration: Duration(seconds: 3),
                ),
              );
            } else {
              throw Exception('ZIP creation timed out');
            }
            return;
          }
          
          // Case 3: Signed URLs - either for individual downloads or client-side ZIP
          if (files == null || files.isEmpty) {
            throw Exception('No files or downloadUrl in 200 response');
          }
          
          final filesList = files.cast<Map<String, dynamic>>();
          final totalFiles = data['totalFiles'] as int;
          final totalSizeMB = data['totalSizeMB'] as int;
          final mode = data['mode'] as String? ?? 'clientZip'; // Default to clientZip for backwards compat
          final message = data['message'] as String?;

          // For very large files (>150MB), download individually without ZIP
          if (mode == 'individual') {
            ScaffoldMessenger.of(context).clearSnackBars();
            
            // Check if download is already in progress
            if (_isDownloadingRecordings) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Download already in progress. Please wait for it to complete.'),
                  duration: Duration(seconds: 5),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            
            // Show initial message with file count and total size
            final sizeGB = (totalSizeMB / 1024).toStringAsFixed(1);
            final estimatedMinutes = (totalFiles * 5 / 60).ceil();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  message ?? 
                  'Starting sequential download of $totalFiles files (${sizeGB}GB total). '
                  'This will take approximately $estimatedMinutes minutes. '
                  'DO NOT close this tab during download!'
                ),
                duration: Duration(seconds: 10),
                backgroundColor: Colors.blue[700],
              ),
            );
            
            // Wait a moment for user to see the message
            await Future.delayed(Duration(seconds: 3));
            
            // Set download flag
            setState(() {
              _isDownloadingRecordings = true;
            });
            
            try {
              // Download files sequentially with proper delays
              // This prevents browser queue overflow and ensures all downloads complete
              await _downloadFilesSequentially(filesList, totalFiles);
            } finally {
              // Clear download flag
              setState(() {
                _isDownloadingRecordings = false;
              });
            }
            
            return;
          }

          // Clear and show initial progress for client-side ZIP
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloading files for ZIP... 0%'),
              duration: Duration(seconds: 120),
            ),
          );

          // Create ZIP in browser (for files 10-150MB)
          final archive = Archive();
          
          for (var i = 0; i < filesList.length; i++) {
            final fileData = filesList[i];
            final url = fileData['url'] as String;
            final name = fileData['name'] as String;
            
            // Download file
            final fileResponse = await http.get(Uri.parse(url));
            
            // Add to archive (store mode - no compression)
            archive.addFile(ArchiveFile(
              name,
              fileResponse.bodyBytes.length,
              fileResponse.bodyBytes,
            ),);

            // Update progress after each file
            final percentComplete = ((i + 1) / filesList.length * 100).toInt();
            
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Creating ZIP... $percentComplete% (${i + 1}/$totalFiles)'),
                duration: Duration(seconds: 120),
              ),
            );
          }

          // Encode archive (store mode)
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Finalizing ZIP...'),
              duration: Duration(seconds: 5),
            ),
          );

          final zipBytes = ZipEncoder().encode(archive, level: Deflate.NO_COMPRESSION);
          
          if (zipBytes == null) {
            throw Exception('Failed to create ZIP');
          }

          // Trigger download
          final blob = html.Blob([Uint8List.fromList(zipBytes)]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', 'recordings-${event.id}.zip')
            ..setAttribute('target', '_blank');
          
          anchor.click();
          
          // Small delay to ensure download initiates
          await Future.delayed(Duration(milliseconds: 200));
          
          html.Url.revokeObjectUrl(url);

          // Clear ALL snackbars
          ScaffoldMessenger.of(context).clearSnackBars();
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          throw Exception('Failed to get recording files: ${response.statusCode}');
        }
      },
    );
  }

  Future<String?> _pollForZipCompletion(String jobId, int estimatedTimeSec) async {
    const pollIntervalSec = 3;
    final maxAttempts = (estimatedTimeSec / pollIntervalSec).ceil() + 10; // Extra buffer
    
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(Duration(seconds: pollIntervalSec));
      
      try {
        final jobDoc = await FirebaseFirestore.instance
            .collection('recordingJobs')
            .doc(jobId)
            .get();
        
        if (!jobDoc.exists) {
          print('Job $jobId not found in Firestore');
          continue;
        }
        
        final jobData = jobDoc.data()!;
        final status = jobData['status'] as String?;
        final downloadUrl = jobData['downloadUrl'] as String?;
        final progress = jobData['progress'] as int? ?? 0;
        
        print('Job $jobId status: $status, progress: $progress%');
        
        if (status == 'completed' && downloadUrl != null) {
          return downloadUrl;
        } else if (status == 'error') {
          final errorMessage = jobData['message'] as String? ?? 'Unknown error';
          throw Exception('ZIP creation failed: $errorMessage');
        }
        
        // Update snackbar with progress (only clear and replace if needed)
        // Keep showing continuously - no flickering
        if (progress > 0 && attempt > 0) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Creating ZIP... $progress%'),
              duration: Duration(seconds: estimatedTimeSec * 2), // Long duration - we'll manually dismiss
            ),
          );
        }
      } catch (e) {
        print('Error polling job $jobId: $e');
        // Continue polling despite errors
      }
    }
    
    return null; // Timeout
  }

  /// Downloads files sequentially with proper delays to handle large-scale downloads
  /// This method ensures all files download even in extreme cases (2500+ files)
  Future<void> _downloadFilesSequentially(
    List<Map<String, dynamic>> filesList, 
    int totalFiles
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
          _buildRowEntry(
            width: 170,
            child: _buildRecordingSection(event),
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
