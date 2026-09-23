Future<bool> checkCanAutoplayFutureFromExternalImpl(
  dynamic Function() checkCanAutoplay,
) async =>
    checkCanAutoplay() as bool;
