import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';

/// Marks a control whose contents have something new behind them.
///
/// A dot rather than a count: this goes on the 24px icons in the mobile
/// control bar, where a number would either be unreadable or wider than the
/// button it sits on. The desktop rail has room for the count and keeps it.
///
/// The dot is excluded from semantics on purpose. It carries its meaning by
/// appearance alone, so a screen reader that announced it would say "red dot"
/// and nothing useful. **The control this wraps must say the same thing in
/// its own accessible name** -- see the chat button in the mobile control
/// bar, whose tooltip becomes "Chat, 3 unread messages".
class UnreadDot extends StatelessWidget {
  /// The control being marked.
  final Widget child;
  final bool show;

  /// The colour immediately behind the dot. The ring drawn in it is what
  /// separates the dot from the glyph it overlaps -- without it the two merge
  /// into one shape at this size.
  final Color background;

  const UnreadDot({
    required this.child,
    required this.show,
    required this.background,
    Key? key,
  }) : super(key: key);

  static const double _size = 9;
  static const double _ring = 2;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2,
          right: -2,
          child: ExcludeSemantics(
            child: Container(
              height: _size + _ring * 2,
              width: _size + _ring * 2,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  height: _size,
                  width: _size,
                  decoration: BoxDecoration(
                    // Reads as "attention" and clears 3:1 against the bar in
                    // both themes -- #a0000b on white, #ffb4ab on neutral900.
                    color: context.theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
