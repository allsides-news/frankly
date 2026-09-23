import 'dart:js_interop';

Future<bool> checkCanAutoplayFutureFromExternalImpl(
  dynamic Function() checkCanAutoplay,
) async {
  final promise = checkCanAutoplay() as JSPromise<JSAny?>;
  final resolved = await promise.toDart;
  return (resolved?.dartify() as bool?) ?? false;
}
