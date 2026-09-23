import 'dart:async';
import 'dart:convert';

import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:node_http/node_http.dart' as http;

AnalyticsUtil analyticsUtil = AnalyticsUtil();

class AnalyticsUtil {
  String get _secretKey => functions.config.get('segment.write_key') as String;

  /// Call to track a user event.
  ///
  /// Returns the delivery future so callers can await it (cloud functions
  /// may freeze background work once the HTTP response closes) or opt out
  /// explicitly with unawaited().
  Future<void> logEvent({
    required String userId,
    required AnalyticsEvent event,
  }) {
    return _doLogEvent(userId: userId, event: event);
  }

  Future<void> _doLogEvent({
    required String userId,
    required AnalyticsEvent event,
  }) async {
    final encodedKey = base64.encode(('$_secretKey:').codeUnits);
    final headers = {
      'Authorization': 'Basic $encodedKey',
      "Content-Type": 'application/json',
    };

    final body = {
      'event': event.getEventType(),
      'properties': event.toJson(),
      'userId': userId,
    };

    final response = await http.post(
      Uri.parse('https://api.segment.io/v1/track'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode > 299) {
      print('Segment POST error:');
      print(response.body);
    }
  }
}
