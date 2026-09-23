import 'package:client/core/utils/check_can_autoplay_future_stub.dart'
    if (dart.library.html) 'package:client/core/utils/check_can_autoplay_future_web.dart';

/// Bridges JS `checkCanAutoplay()` (Promise on web, bool on stub) to [Future<bool>].
Future<bool> checkCanAutoplayFutureFromExternal(dynamic Function() checkCanAutoplay) =>
    checkCanAutoplayFutureFromExternalImpl(checkCanAutoplay);
