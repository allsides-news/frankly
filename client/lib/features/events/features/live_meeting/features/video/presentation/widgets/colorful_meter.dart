import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/features/user/presentation/widgets/user_profile_chip.dart';
import 'package:rainbow_color/rainbow_color.dart';

/// Gauge widget inspired from https://pub.dev/packages/pretty_gauge .
/// Paints gauge ([_ArcPainter]) in gradient colors and shows [_GaugeIndicatorClipper]
/// in range of [0:1].
///
/// [value] is the value of the [_GaugeIndicatorClipper].
/// [size] is the optional size of the widget. If [size] is not provided, it will take parent's size.
/// [userId] is shown as a profile picture centered in the ring.
/// [timeText] is shown in a pill overlapping the bottom of the ring, next
/// to a speech-bubble icon. [pillColor] should match whatever background
/// this meter is placed on, so the pill reads as part of that background
/// rather than a separate box.
class ColorfulMeter extends StatefulWidget {
  final double value;
  final double? size;
  final String? userId;
  final String? timeText;
  final Color pillColor;

  @override
  _ColorfulMeterState createState() => _ColorfulMeterState();

  const ColorfulMeter({
    Key? key,
    required this.value,
    required this.pillColor,
    this.size,
    this.userId,
    this.timeText,
  })  : assert(value >= -1 && value <= 1, 'value must be between -1 and 1'),
        super(key: key);
}

class _ColorfulMeterState extends State<ColorfulMeter> {
  /// Default size of the widget.
  static const double kDefaultSize = 100;

  /// Ring takes this fraction of the overall widget size, leaving the rest
  /// for the time row below it.
  static const double _kRingFraction = 0.72;

  @override
  Widget build(BuildContext context) {
    final currentValue = widget.value;

    const double startingIndicatorAngle = math.pi;
    // 0.6 because we draw arc slightly more than half of rect. Half of rect - 0.5.
    final double endingIndicatorAngle = currentValue * 0.6 * math.pi;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double sizeFromConstraints;
        // Calculations for backup size.
        if (constraints.maxWidth != double.infinity) {
          sizeFromConstraints = constraints.maxWidth;
        } else if (constraints.maxHeight != double.infinity) {
          sizeFromConstraints = constraints.maxHeight;
        } else {
          sizeFromConstraints = kDefaultSize;
        }

        final double size;

        // If widget size is provided but parent's size is smaller than provided size,
        // use maximum size available within the parent.
        if (constraints.maxWidth < (widget.size ?? 0)) {
          size = constraints.maxWidth;
        } else if (constraints.maxHeight < (widget.size ?? 0)) {
          size = constraints.maxHeight;
        } else {
          size = widget.size ?? sizeFromConstraints;
        }

        final ringSize = size * _kRingFraction;

        // Using only for retrieving correct color from same color spectrum, which is used
        // in rendering gauge arc line.
        final rainbow = Rainbow(
          spectrum: kOdometerColors,
          rangeStart: 1,
          rangeEnd: -1,
        );

        return ClipRect(
          child: SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(ringSize, ringSize),
                  painter: _ArcPainter(),
                ),
                Transform.rotate(
                  angle: startingIndicatorAngle + endingIndicatorAngle,
                  child: ClipPath(
                    clipper: _GaugeIndicatorClipper(),
                    child: Container(color: rainbow[currentValue]),
                  ),
                ),
                // UserInfoBuilder (via UserProfileChip) force-unwraps its
                // userId, so guard against the local participant not being
                // resolved yet (room connecting/disconnected) instead of
                // crashing the meeting UI.
                if (widget.userId != null)
                  UserProfileChip(
                    userId: widget.userId,
                    showName: false,
                    showBorder: false,
                    enableOnTap: false,
                    alignment: Alignment.center,
                    imageHeight: ringSize * 0.56,
                  )
                else
                  _buildAvatarPlaceholder(context, ringSize * 0.56),
                // Overlaps the bottom of the ring/avatar so the time reads
                // as part of the same element instead of a separate line
                // below it. FittedBox absorbs the sub-pixel rounding between
                // the pill's intrinsic width and the ring's width that was
                // otherwise tripping a RenderFlex overflow in debug mode.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _buildPill(context, size),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarPlaceholder(BuildContext context, double diameter) {
    return Container(
      height: diameter,
      width: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.theme.colorScheme.surfaceContainer,
      ),
    );
  }

  Widget _buildPill(BuildContext context, double size) {
    final timeText = widget.timeText;
    if (timeText == null) return const SizedBox.shrink();

    final fontSize = size / 8;
    // Follows the pill, which now follows the theme.
    final color = context.theme.colorScheme.onSurface;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.09,
        vertical: size * 0.03,
      ),
      decoration: BoxDecoration(
        color: widget.pillColor,
        borderRadius: BorderRadius.circular(size * 0.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(FontAwesomeIcons.solidComment, size: fontSize, color: color),
          SizedBox(width: size * 0.04),
          HeightConstrainedText(
            timeText,
            maxLines: 1,
            style: TextStyle(fontSize: fontSize, color: color),
          ),
        ],
      ),
    );
  }
}

class _GaugeIndicatorClipper extends CustomClipper<Path> {
  // This comment bellow is from library mentioned above - not sure if it's legit.
  //
  // Note that x,y coordinate system starts at the bottom right of the canvas
  // with x moving from right to left and y moving from bottom to top.
  // Bottom right is 0,0 and top left is x,y.
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.95);
    path.lineTo(size.width * 0.55, size.height);
    path.lineTo(size.width * 0.7, size.height);
    path.lineTo(size.width * 0.45, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}

/// Painter which draws the gradient line of the [ColorfulMeter].
class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final widthOfColorfulLine = size.width * 0.075;

    // Making rect slightly smaller because we need to use an indicator outside it.
    final rect = Rect.fromLTRB(
      size.width * 0.1,
      size.height * 0.1,
      size.width * 0.9,
      size.height * 0.9,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = widthOfColorfulLine
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.bottomLeft,
        colors: kOdometerColors,
      ).createShader(rect);

    // Voodoo math to match drawn arc to UI Design.
    canvas.drawArc(rect, 0.9 * math.pi, 1.2 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
