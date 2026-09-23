import 'package:client/core/utils/validation_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isEmailValid', () {
    test('accepts common emails', () {
      expect(isEmailValid('heather@gmail.com'), isTrue);
      expect(isEmailValid('first.last@allsides.com'), isTrue);
      expect(isEmailValid('user+tag@example.com'), isTrue);
    });

    test('accepts hyphens in local and domain parts', () {
      expect(isEmailValid('test-dashes@dashes.com'), isTrue);
      expect(isEmailValid('dashes@testing-dashes.com'), isTrue);
      expect(isEmailValid('heather@independent-voices.org'), isTrue);
    });

    test('trims whitespace before validating', () {
      expect(isEmailValid('  user@example.com  '), isTrue);
      expect(isEmailValid('dashes@testing-dashes.com '), isTrue);
    });

    test('rejects malformed emails', () {
      expect(isEmailValid(''), isFalse);
      expect(isEmailValid('not-an-email'), isFalse);
      expect(isEmailValid('@nodomain.com'), isFalse);
      expect(isEmailValid('missing-at.com'), isFalse);
      expect(isEmailValid('trailing-dot@domain.'), isFalse);
      expect(isEmailValid('bad@-domain.com'), isFalse);
      expect(isEmailValid('bad@domain-.com'), isFalse);
    });
  });
}
