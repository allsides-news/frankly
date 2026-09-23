import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/cupertino.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/networking_status_contract.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/models/networking_status_model.dart';
import 'package:client/services.dart';
import 'package:provider/provider.dart';

import '../data/providers/agora_room.dart';

class NetworkingStatusPresenter {
  /// Hold a time duration for how long it should wait until [_isLowNetworkQuality]
  /// should become true.
  static const Duration _kPrimaryThresholdDuration = Duration(seconds: 5);

  final NetworkingStatusView _view;
  final NetworkingStatusModel _model;
  final ConferenceRoom _conferenceRoom;
  bool _lastWasBad = false;

  NetworkingStatusPresenter(
    BuildContext context,
    this._view,
    this._model, {
    ConferenceRoom? conferenceRoom,
  }) : _conferenceRoom = conferenceRoom ?? context.read<ConferenceRoom>();

  static const _badStates = [
    QualityType.qualityPoor,
    QualityType.qualityVbad,
    QualityType.qualityBad,
    QualityType.qualityDown,
  ];

  bool get _isUplinkBad => _badStates.contains(_model.uplinkQuality);
  bool get _isDownlinkBad => _badStates.contains(_model.downlinkQuality);
  bool get _isAnyLinkBad => _isUplinkBad || _isDownlinkBad;

  /// True while the Agora connection dropped and the SDK is re-establishing
  /// it (set from the client bridge's connection-state events).
  bool get isReconnecting =>
      _conferenceRoom.room?.state == AgoraRoomState.RECONNECTING;

  void updateNetworkQuality() {
    final AgoraRoom? room = _conferenceRoom.room;
    _model.uplinkQuality = room?.localParticipant?.uplinkQuality;
    _model.downlinkQuality = room?.localParticipant?.downlinkQuality;

    if (_isAnyLinkBad) {
      final Timer? timer = _model.timer;
      if (!_lastWasBad) {
        loggingService.log(
          'NetworkingStatusPresenter.updateNetworkQuality: Bad network detected',
        );
        _lastWasBad = true;
      }

      // Only spawn new timer if it's not initialised (first time) or active already
      if (timer == null || !timer.isActive) {

        _model.timer = Timer.periodic(_kPrimaryThresholdDuration, (timer) {
          if (_isAnyLinkBad) {
            loggingService.log(
              'NetworkingStatusPresenter.updateNetworkQuality: Bad network for more than $_kPrimaryThresholdDuration',
            );
            _model.isLowNetworkQuality = true;

            // Reset dismissed state if cooldown has expired
            if (_model.isLowNetworkQualityMessageDismissed &&
                _model.isCooldownExpired) {
              _model.isLowNetworkQualityMessageDismissed = false;
            }

            _view.updateView();
          } else {
            _model.isLowNetworkQuality = false;
            _view.updateView();

            loggingService.log(
              'NetworkingStatusPresenter.updateNetworkQuality: Connection improved',
            );
            timer.cancel();
          }
        });
      }
    }
    // If network conditions improve
    else {
      if (_lastWasBad) {
        loggingService.log(
          'NetworkingStatusPresenter.updateNetworkQuality: Network improved',
        );
        _lastWasBad = false;
      }
      if (_model.isLowNetworkQuality) {
        _model.isLowNetworkQuality = false;
        _view.updateView();
      }

      _model.timer?.cancel();
    }
  }

  void dismissLowNetworkQualityMessage() {
    _model.isLowNetworkQualityMessageDismissed = true;
    _model.dismissedAt = clockService.now();
    _view.updateView();
  }

  /// Alert copy differentiated by which direction is bad, because the
  /// useful user action differs: a bad uplink can be helped by turning the
  /// camera off; a bad downlink cannot.
  ///
  /// The camera-off suggestion requires the downlink to be healthy: outgoing
  /// bandwidth estimation depends on feedback arriving over the downlink, so
  /// a starved downlink makes the SDK report the uplink as bad too (QA
  /// measured tx "bad" with OUT limit=none at 100 Kbps down / 2 Mbps up).
  /// When both read bad we cannot tell which direction is really broken, and
  /// advising camera-off on a downlink problem sends the user the wrong way.
  String getMessage() {
    if (_isUplinkBad && !_isDownlinkBad) {
      return 'Your upload connection is struggling — others may see and '
          'hear you poorly. Turning off your camera can help.';
    }
    return 'Your connection is spotty — you may experience audio/video '
        'issues';
  }

  void dispose() {
    _model.timer?.cancel();
  }

  Widget getCorrectWidget({
    required Widget nothing,
    required Widget networkStatusAlert,
    required Widget reconnectingAlert,
  }) {
    // Reconnecting outranks the quality warning: the connection is DOWN,
    // and the banner is not dismissible (it clears itself on recovery).
    if (isReconnecting) {
      return reconnectingAlert;
    }
    if (_model.isLowNetworkQuality &&
        !_model.isLowNetworkQualityMessageDismissed) {
      return networkStatusAlert;
    } else {
      return nothing;
    }
  }
}
