import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:client/core/widgets/proxied_image.dart';

import 'package:client/styles/app_asset.dart';

/// This is an icon that appears in the top or bottom nav bar. If it is selected it shows a solid
/// indicator line below the icon. The size of the icon and spacing between it and the indicator
/// can be manually set in the case of slightly differently sized icons / images, but they are
/// intended to appear the same size and distance apart on screen. Either iconData or a local image
/// path is required.
class SelectableNavigationIcon extends StatelessWidget {
  final bool isSelected;
  final IconData? iconData;
  final AppAsset? imagePath;
  final AppAsset? selectedImagePath;
  final void Function()? onTap;
  final double iconSize;

  /// Drops the default 48px minimum tap box down to the icon plus a few
  /// pixels, for rows that have to fit several icons in a constrained space
  /// (e.g. the Space nav pill on mobile).
  final bool dense;

  /// Whitespace left between two adjacent icons in a [dense] row -- half of it
  /// sits on each side of every icon.
  ///
  /// A parameter rather than a constant because the row that uses it has to
  /// fit a fixed set of icons into whatever width the screen leaves: it spends
  /// spare width here and gives it back first when there is none.
  final double denseGap;

  /// What a dense row uses when there is room for it.
  static const double defaultDenseGap = 22.5;

  /// The tightest a dense row will squeeze to. Below this the icons start
  /// reading as one undifferentiated strip and the tap targets collide.
  static const double minDenseGap = 10.0;

  /// Names the destination for assistive technology, and doubles as the hover
  /// (or long-press) tooltip.
  ///
  /// Required, not optional: this control is icon-only, so omitting it leaves
  /// a screen reader nothing to announce but "button" -- a WCAG failure that
  /// is invisible in normal use and so easy to reintroduce.
  final String label;

  const SelectableNavigationIcon({
    Key? key,
    required this.isSelected,
    this.iconData,
    this.imagePath,
    this.selectedImagePath,
    this.onTap,
    this.iconSize = 30.0,
    this.dense = false,
    this.denseGap = defaultDenseGap,
    required this.label,
  })  : assert(iconData != null || imagePath != null),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          // IconButton feeds `tooltip` to Semantics as well, so this both
          // names the control and gives sighted users a hover hint.
          tooltip: label,
          padding: dense
              ? EdgeInsets.symmetric(horizontal: denseGap / 2, vertical: 5)
              : null,
          constraints: dense ? const BoxConstraints() : null,
          style: dense
              ? IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )
              : null,
          icon: iconData != null
              ? Icon(
                  iconData,
                  size: iconSize,
                  color: isSelected
                      ? context.theme.colorScheme.onSurface
                      : context.theme.colorScheme.onSurfaceVariant,
                )
              : ProxiedImage(
                  null,
                  asset: isSelected ? selectedImagePath : imagePath,
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.cover,
                ),
        ),
        if (isSelected) ...[
          Container(
            height: 2,
            width: 24,
            color: context.theme.colorScheme.primary,
          ),
        ],
      ],
    );
  }
}
