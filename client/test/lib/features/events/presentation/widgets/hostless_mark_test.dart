import 'package:client/features/events/presentation/widgets/hostless_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HostlessMark paints without loading an asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostlessMark(color: Color(0xFF112233)),
        ),
      ),
    );

    expect(find.byType(HostlessMark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
