import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String readSidebarPlatformVersion(Object window) {
  final win = window as JSObject;
  final value = win['platformVersion'];
  return value?.dartify()?.toString() ?? 'unknown';
}
