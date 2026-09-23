import 'dart:async';

import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import 'cloud_function.dart';
import 'utils/infra/firestore_utils.dart';
import 'package:data_models/cloud_functions/requests.dart';

/// Class for onCall methods. These are requests that are mostly called from
/// our client apps.
///
/// Request types should be defined in data_models.
abstract class OnCallMethod<T extends SerializeableRequest>
    implements CloudFunction {
  @override
  final String functionName;

  /// Function that converts request JSON into a request object.
  T Function(dynamic data) requestFromData;

  final RuntimeOptions? runWithOptions;

  OnCallMethod(
    this.functionName,
    this.requestFromData, {
    this.runWithOptions,
  });

  Future<dynamic> action(T request, CallableContext context);

  Future<dynamic> callAction(dynamic data, CallableContext context) async {
    try {
      print('getting request');
      final request = requestFromData(firestoreUtils.fromFirestoreJson(data));

      // Print the request for debug purposes
      print(request);

      final result = await action(request, context);
      return result ?? {};
    } catch (e, stacktrace) {
      print('Error during action $functionName');
      print(e);
      print(stacktrace);
      // The interop layer's _toJsHttpsError crashes on null details
      // (jsify(null) throws a JSNull TypeError in dart2js), which turns
      // intended error codes like not-found into opaque unhandled internal
      // errors on the client. Substitute empty details so the real code and
      // message survive the JS conversion.
      if (e is HttpsError && e.details == null) {
        throw HttpsError(e.code, e.message, '');
      }
      rethrow;
    }
  }

  @override
  void register(FirebaseFunctions functions) {
    functions[functionName] = functions
        .runWith(
          runWithOptions ??
              RuntimeOptions(
                timeoutSeconds: 60,
                memory: '1GB',
                minInstances: 0,
              ),
        )
        .https
        .onCall(callAction);
  }
}
