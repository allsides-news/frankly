import 'dart:js_interop';

Future<T> irisPromiseToFuture<T>(Object jsPromise) =>
    (jsPromise as JSPromise<JSAny?>).toDart.then((value) {
      if (value == null) {
        throw StateError(
          'irisPromiseToFuture: JS Promise resolved to null (non-nullable result expected)',
        );
      }
      if (value is! T) {
        throw StateError(
          'irisPromiseToFuture: expected $T',
        );
      }
      return value as T;
    });
