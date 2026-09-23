import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void callWindowPickMedia(
  Object window,
  Map<String, Object?> parameters,
  void Function(Object? error, Object? result) callback,
) {
  final win = window as JSObject;
  win.callMethodVarArgs('pickMedia'.toJS, [
    parameters.jsify(),
    ((JSAny? error, JSAny? result) {
      callback(error?.dartify(), result?.dartify());
    }).toJS,
  ]);
}
