import 'package:client/core/widgets/navbar/nav_bar/space_pill_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inner content height equals the logo after padding and border', () {
    expect(
      kSpacePillHeight - kSpacePillPadding * 2 - kSpacePillBorderWidth * 2,
      kSpaceLogoSize,
    );
  });

  testWidgets(
    'space pill height includes the border so the logo does not overflow',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: _SpacePillBoxModel(),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

/// Same box model as [_buildSpacePillBody]: fixed height, 1px border inside
/// that height, padding, then a [kSpaceLogoSize] child.
class _SpacePillBoxModel extends StatelessWidget {
  const _SpacePillBoxModel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kSpacePillHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kSpacePillRadius),
        border: Border.all(width: kSpacePillBorderWidth),
      ),
      padding: const EdgeInsets.all(kSpacePillPadding),
      child: const SizedBox(
        width: kSpaceLogoSize,
        height: kSpaceLogoSize,
      ),
    );
  }
}
