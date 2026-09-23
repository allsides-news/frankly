import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/ready_to_advance_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'desktop host Back+Next fit in the 200px rail without overflow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ReadyToAdvanceBar.shell(
                isMobile: false,
                child: ReadyToAdvanceBar(
                  participants: const [],
                  hasVoted: false,
                  isHost: true,
                  showBackButton: true,
                  onNext: () {},
                  onBack: () {},
                  isMobile: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    },
  );
}
