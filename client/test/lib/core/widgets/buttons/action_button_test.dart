import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubmitNotifier', () {
    test('submit completes if a listener unregisters during the await', () async {
      final notifier = SubmitNotifier();
      late Future<void> Function() listener;
      listener = () async {
        await Future<void>.delayed(Duration.zero);
        notifier.removeListener(listener);
      };
      notifier.addListener(listener);

      await expectLater(notifier.submit(), completes);
    });
  });
}
