import 'package:client/core/data/services/matomo_send_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matomoSendDecision', () {
    test('skips when tracking is disabled', () {
      expect(
        matomoSendDecision(
          trackingEnabled: false,
          trackerInitialized: true,
          initFailed: false,
        ),
        MatomoSendDecision.skip,
      );
    });

    test('skips after init failed even if tracking is still enabled', () {
      expect(
        matomoSendDecision(
          trackingEnabled: true,
          trackerInitialized: false,
          initFailed: true,
        ),
        MatomoSendDecision.skip,
      );
    });

    test('waits when tracking is on and init has not finished', () {
      expect(
        matomoSendDecision(
          trackingEnabled: true,
          trackerInitialized: false,
          initFailed: false,
        ),
        MatomoSendDecision.waitForInit,
      );
    });

    test('sends when the tracker is initialized', () {
      expect(
        matomoSendDecision(
          trackingEnabled: true,
          trackerInitialized: true,
          initFailed: false,
        ),
        MatomoSendDecision.sendNow,
      );
    });
  });
}
