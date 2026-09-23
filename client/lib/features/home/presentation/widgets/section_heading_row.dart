import 'package:client/core/widgets/section_heading.dart';
import 'package:flutter/material.dart';

/// A home-page section's heading, with an optional action on its right.
///
/// The row is the same height whether or not it carries an action. Featured
/// and Following sit side by side on desktop, and "Start a Space" is half
/// again as tall as the heading text -- left to size itself, the section with
/// the button pushed its heading and its whole strip of cards down relative
/// to the section beside it.
class SectionHeadingRow extends StatelessWidget {
  final String text;
  final Widget? trailing;

  /// [CircleIconButton]'s height -- a 24px icon inset by 10 on every side.
  /// The tallest thing that goes in this row, and so what sets its height.
  static const double height = 44;

  const SectionHeadingRow(this.text, {this.trailing, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SectionHeading(text),
          if (trailing != null) ...[
            Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
