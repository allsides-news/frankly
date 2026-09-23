import 'package:client/core/widgets/tabs/tab_bar_view.dart';
import 'package:client/core/widgets/tabs/tab_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'CustomTabBarView does not wrap tabs in a tap-to-unfocus detector',
      (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTabController(
            tabs: [
              CustomTabAndContent(
                tab: 'chat',
                content: (context) => TextField(focusNode: focusNode),
              ),
            ],
            child: const CustomTabBarView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(
      tester
          .element(find.byType(IndexedStack))
          .findAncestorWidgetOfExactType<GestureDetector>(),
      isNull,
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
  });
}
