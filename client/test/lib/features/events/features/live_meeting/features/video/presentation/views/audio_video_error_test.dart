import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_error.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'NotAllowedError as a join wall offers listen-only continue, not only Refresh',
    (tester) async {
      var continued = false;
      await tester.pumpWidget(
        _app(
          AudioVideoErrorDisplay(
            error: 'NotAllowedError: Permission denied',
            onJoinWithoutDevices: () => continued = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Camera or microphone isn\'t available. You can still join and listen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Join without camera or microphone'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.tap(find.text('Join without camera or microphone'));
      expect(continued, isTrue);
    },
  );

  testWidgets(
    'NotAllowedError without continue still maps to the permission-required wall',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const AudioVideoErrorDisplay(
            error: 'NotAllowedError: Permission denied',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Permission to use audio/video devices is required.'),
        findsOneWidget,
      );
      expect(find.text('Join without camera or microphone'), findsNothing);
      expect(find.text('Refresh'), findsOneWidget);
    },
  );

  testWidgets(
    'in-meeting NotAllowedError asks for permission with Close, not the '
    'pre-join listen-only copy',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const AudioVideoErrorDisplay(
            error: 'NotAllowedError: Permission denied',
            inMeeting: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Permission to use audio/video devices is required.'),
        findsOneWidget,
      );
      expect(find.text('Refresh'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Join without camera or microphone'), findsNothing);
    },
  );

  testWidgets(
    'in-meeting busy camera uses Close instead of Refresh',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const AudioVideoErrorDisplay(
            error: 'NotReadableError: Could not start video source',
            inMeeting: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("Audio/video device can't be read or is busy."),
        findsOneWidget,
      );
      expect(find.text('Refresh'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    },
  );
}
