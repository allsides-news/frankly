import 'package:client/core/routing/locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('queryParametersWithJoinedStatus', () {
    test('returns null when status is already joined', () {
      expect(
        queryParametersWithJoinedStatus({'status': 'joined', 'b': '1'}),
        isNull,
      );
    });

    test('adds status=joined without dropping other params', () {
      expect(
        queryParametersWithJoinedStatus({'b': '1'}),
        {'b': '1', 'status': 'joined'},
      );
    });
  });
}
