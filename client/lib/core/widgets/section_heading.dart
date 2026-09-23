import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';

/// A section label -- "Upcoming", "About", "Following".
///
/// One definition so these stay typographically identical wherever they
/// appear. Note the explicit [ColorScheme.onSurface]: Spaces can theme
/// `colorScheme.secondary` to white, which renders a heading invisible against
/// the page, so headings must not pick up that colour.
class SectionHeading extends StatelessWidget {
  final String text;

  const SectionHeading(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: HeightConstrainedText(
        text,
        style: AppTextStyle.headline4.copyWith(
          color: context.theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
