import 'dart:async';
import 'dart:math';

import 'package:collection/src/iterable_extensions.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/audio_levels_model.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:client/features/events/features/live_meeting/features/av_check/data/av_check_audio_tracker.dart';
import 'package:client/features/events/features/live_meeting/features/av_check/data/av_check_video.dart';
import 'package:universal_html/html.dart' as html;

class AvCheckProvider with ChangeNotifier {
  static const Size requestedSize = Size(720, 480);

  html.MediaStream? _mediaStream;
  late html.VideoElement _div;
  late String _viewKey;
  BehaviorSubjectWrapper<List?>? _devicesStream;
  late StreamSubscription _devicesSubscription;
  final BuildContext context;

  bool _cameraOn = true;
  bool _micOn = true;
  String? _defaultMic;
  String? _defaultCamera;
  ParticipantAudioLevelTracker? _tracker;
  String? _errorText;
  String? _deviceNotice;

  AvCheckProvider({required this.context});

  html.MediaStream? get mediaStream => _mediaStream;

  html.VideoElement get div => _div;

  bool get cameraOn => _cameraOn;

  bool get micOn => _micOn;

  String? get defaultMic => _defaultMic;

  String? get defaultCamera => _defaultCamera;

  String get viewKey => _viewKey;

  String? get errorText => _errorText;

  /// Non-fatal capture failure; join is still allowed (listen-only).
  String? get deviceNotice => _deviceNotice;

  List<html.MediaDeviceInfo>? get devicesList {
    final raw = _devicesStream?.value;
    if (raw == null) {
      // Stream exists but hasn't emitted; don't block Join behind a spinner.
      if (_devicesStream != null) return const [];
      return null;
    }
    return raw.map((e) => e as html.MediaDeviceInfo).toList();
  }

  int get currentAudioLevel {
    double level = max(_tracker?.currentAudioLevel?.volume ?? -100, -100);
    final adjustedLevel = ((level + 100) / 9).round().clamp(0, 9);
    return adjustedLevel;
  }

  Map<String, dynamic> _videoConstraints({String? deviceId}) {
    return {
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      'width': {'ideal': requestedSize.width},
      'height': {'ideal': requestedSize.height},
      'frameRate': {'ideal': 24},
    };
  }

  Future<html.MediaStream?> _tryGetUserMedia({
    required bool audio,
    required bool video,
    String? audioDeviceId,
    String? videoDeviceId,
  }) async {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) return null;
    return mediaDevices.getUserMedia({
      if (audio)
        'audio': audioDeviceId != null && audioDeviceId.isNotEmpty
            ? {'deviceId': audioDeviceId}
            : true,
      if (video) 'video': _videoConstraints(deviceId: videoDeviceId),
    });
  }

  void _attachPreview() {
    _div.srcObject = _mediaStream;
    if (!_cameraOn) {
      _setVideoTracksEnabled(false);
    }
    _tracker?.dispose();
    _tracker = null;
    _startAudioTrackerIfNeeded();
    _refreshDeviceNotice();
  }

  /// Reconcile the notice with what the stream actually delivers, so a live
  /// preview never sits under a stale "camera isn't available" message after
  /// a device recovers or the user switches to a working one.
  void _refreshDeviceNotice() {
    final hasVideo = _mediaStream?.getVideoTracks().isNotEmpty == true;
    final hasAudio = _mediaStream?.getAudioTracks().isNotEmpty == true;
    if (hasVideo && hasAudio) {
      _deviceNotice = null;
    } else if (hasVideo) {
      _deviceNotice =
          'Microphone isn\'t available. You can still join and listen.';
    } else if (hasAudio) {
      // Keep the more specific blocked-permission text if that's what the
      // failed toggle reported; the camera is genuinely still unavailable.
      if (_deviceNotice?.contains('blocked') != true) {
        _deviceNotice =
            'Camera isn\'t available. You can still join and listen.';
      }
    }
    // No stream at all: leave the notice from the failure path in place.
  }

  void _setVideoTracksEnabled(bool enabled) {
    for (final track in _mediaStream?.getVideoTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  bool _hasLiveVideoTracks() => avCheckHasLiveVideoTrack(
        (_mediaStream?.getVideoTracks() ?? []).map((t) => t.readyState),
      );

  void _startAudioTrackerIfNeeded() {
    if (_tracker != null) return;
    final stream = _mediaStream;
    if (stream == null) return;
    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isEmpty) return;
    _tracker = ParticipantAudioLevelTracker(
      onUpdate: () => notifyListeners(),
      mediaStream: stream,
      trackName: avCheckAudioTrackerName(
        defaultMic: _defaultMic,
        audioTrackId: audioTracks.first.id,
      ),
    )..initialize();
  }

  Future<void> initialize() async {
    // Add a random string in case this page is accessed a second time before the tab is reloaded
    _viewKey = 'avCheck-${Random().nextDouble()}';
    _div = html.VideoElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..muted = true
      ..autoplay = true;
    registerWebViewFactory(_viewKey, (_) {
      return _div;
    });

    // Combined audio+video is one permission prompt. If it fails (blocked
    // camera, busy device, or the user dismissed the prompt), keep degrading
    // so Join stays available — playback does not need capture.
    try {
      _mediaStream = await _tryGetUserMedia(audio: true, video: true);
    } catch (e) {
      loggingService.log('AvCheck: audio+video getUserMedia failed: $e');
      try {
        _mediaStream = await _tryGetUserMedia(audio: true, video: false);
        _cameraOn = false;
        _deviceNotice =
            'Camera isn\'t available. You can still join and listen.';
      } catch (e2) {
        loggingService.log('AvCheck: audio-only getUserMedia failed: $e2');
        try {
          _mediaStream = await _tryGetUserMedia(audio: false, video: true);
          _micOn = false;
          _deviceNotice =
              'Microphone isn\'t available. You can still join and listen.';
        } catch (e3) {
          loggingService.log('AvCheck: video-only getUserMedia failed: $e3');
          _cameraOn = false;
          _micOn = false;
          _deviceNotice =
              'Camera and microphone aren\'t available. You can still join and listen.';
        }
      }
    }

    if (_mediaStream == null) {
      _cameraOn = false;
      _micOn = false;
      _deviceNotice ??=
          'Camera and microphone aren\'t available. You can still join and listen.';
    }

    _attachPreview();

    _devicesStream = wrapInBehaviorSubject(
      html.window.navigator.mediaDevices?.enumerateDevices().asStream() ??
          Stream.value(<html.MediaDeviceInfo>[]),
    );

    _devicesSubscription = _devicesStream!.listen((devices) {
      if (_defaultMic == null || _defaultCamera == null) {
        _setDefaults();
        if (shouldRetryAvCheckAudioTracker(
          trackerAttached: _tracker != null,
          hasAudioTracks: _mediaStream?.getAudioTracks().isNotEmpty == true,
        )) {
          _startAudioTrackerIfNeeded();
        }
      }
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> _getMediaStream() async {
    final wantVideo = _defaultCamera != null && _defaultCamera!.isNotEmpty;
    final wantAudio = _defaultMic != null && _defaultMic!.isNotEmpty;
    if (!wantVideo && !wantAudio) return;

    try {
      final newMediaStream = await _tryGetUserMedia(
        audio: wantAudio,
        video: wantVideo,
        audioDeviceId: _defaultMic,
        videoDeviceId: _defaultCamera,
      );
      _mediaStream?.getTracks().forEach((track) => stopMediaTrack(track));
      _mediaStream = newMediaStream;
      _attachPreview();
      notifyListeners();
    } catch (e) {
      loggingService.log('AvCheck: device switch getUserMedia failed: $e');
    }
  }

  @override
  void dispose() {
    _tracker?.dispose();
    _mediaStream?.getTracks().forEach((track) => stopMediaTrack(track));
    _div.srcObject = null;
    _devicesStream?.dispose();
    _devicesSubscription.cancel();
    super.dispose();
  }

  void joinNowPressed() {
    sharedPreferencesService.setAvCheckComplete(
      cameraOnByDefault: _cameraOn,
      micOnByDefault: _micOn,
      defaultCamera: _defaultCamera ?? '',
      defaultMic: _defaultMic ?? '',
    );
    updateQueryParameterToJoinEvent();
  }

  /// Leave the permission wall and continue into the join UI listen-only.
  void continueWithoutDevices() {
    _errorText = null;
    _cameraOn = false;
    _micOn = false;
    _deviceNotice =
        'Camera and microphone aren\'t available. You can still join and listen.';
    notifyListeners();
  }

  void _setDefaults() {
    final cameraDevices = devicesList?.where((d) => d.kind == 'videoInput');
    final micDevices = devicesList?.where((d) => d.kind == 'audioInput');
    _defaultCamera ??= cameraDevices
            ?.firstWhereOrNull(
              (d) =>
                  d.deviceId == sharedPreferencesService.getDefaultCameraId(),
            )
            ?.deviceId ??
        cameraDevices?.firstOrNull?.deviceId;
    _defaultMic ??= micDevices
            ?.firstWhereOrNull(
              (d) =>
                  d.deviceId ==
                  sharedPreferencesService.getDefaultMicrophoneId(),
            )
            ?.deviceId ??
        micDevices?.firstOrNull?.deviceId;
  }

  Future<void> toggleVideo() async {
    if (_cameraOn) {
      _cameraOn = false;
      _setVideoTracksEnabled(false);
      notifyListeners();
      return;
    }
    if (_hasLiveVideoTracks()) {
      _setVideoTracksEnabled(true);
      _cameraOn = true;
      _div.srcObject = _mediaStream;
      _refreshDeviceNotice();
      try {
        await _div.play();
      } catch (_) {}
      notifyListeners();
      return;
    }
    try {
      final keepAudio = _mediaStream?.getAudioTracks().isNotEmpty == true;
      final newStream = await _tryGetUserMedia(
        audio: keepAudio,
        video: true,
        audioDeviceId: keepAudio ? _defaultMic : null,
        videoDeviceId: _defaultCamera,
      );
      if (newStream == null || newStream.getVideoTracks().isEmpty) {
        _deviceNotice =
            'Camera isn\'t available. You can still join and listen.';
        notifyListeners();
        return;
      }
      _mediaStream?.getTracks().forEach((track) => stopMediaTrack(track));
      _mediaStream = newStream;
      _cameraOn = true;
      _attachPreview();
      try {
        await _div.play();
      } catch (_) {}
      notifyListeners();
    } catch (e) {
      loggingService.log('AvCheck: toggle camera on failed: $e');
      // Distinguish blocked from busy/missing: with the camera blocked the
      // generic notice is often already on screen, so a re-toggle looked like
      // a dead button.
      _deviceNotice = e.toString().contains('NotAllowedError')
          ? 'Camera access is blocked. Allow camera access in your browser\'s '
              'site settings to turn on video, or join and listen.'
          : 'Camera isn\'t available. You can still join and listen.';
      notifyListeners();
    }
  }

  void toggleMic() {
    _micOn = !_micOn;
    notifyListeners();
  }

  void selectMic(String info) {
    _defaultMic = info;
    _getMediaStream();
    notifyListeners();
  }

  void selectCamera(String info) {
    _defaultCamera = info;
    _getMediaStream();
    notifyListeners();
  }
}
