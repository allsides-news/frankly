import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:client/services.dart';

class NetworkingStatusModel {
  /// Cooldown duration after user dismisses the toast before it can reappear.
  static const Duration dismissCooldown = Duration(seconds: 60);

  bool isLowNetworkQuality = false;
  bool isLowNetworkQualityMessageDismissed = false;
  DateTime? dismissedAt;

  /// Normalized local link qualities (see AgoraRoom.onNetworkQuality).
  /// Tracked separately so the alert can tell the user whether THEIR send
  /// (others see them poorly) or receive (they see others poorly) is bad.
  QualityType? uplinkQuality;
  QualityType? downlinkQuality;
  Timer? timer;

  /// Whether the cooldown period has elapsed since the user last dismissed.
  bool get isCooldownExpired {
    if (dismissedAt == null) return true;
    return clockService.now().difference(dismissedAt!) >= dismissCooldown;
  }
}
