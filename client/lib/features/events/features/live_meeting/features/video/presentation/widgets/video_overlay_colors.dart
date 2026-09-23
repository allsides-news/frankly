import 'package:flutter/material.dart';

/// Colours for anything drawn on top of a video tile.
///
/// Constants, not theme tokens. What sits behind these is someone's camera
/// feed -- bright or dark, changing frame to frame -- so a pair chosen for the
/// app's own surfaces says nothing about whether the result is readable. Every
/// overlay here used `scrim` at 32% opacity with a token foreground, which
/// came out mid-grey over a light frame and near-black over a dark one; no
/// token could sit on both, and the ones in use sat on neither.
class VideoOverlayColors {
  VideoOverlayColors._();

  /// Opaque enough that white clears 4.5:1 over the brightest frame a camera
  /// can produce: 70% black over white is #4D4D4D, which white reads against
  /// at about 8:1.
  static const Color plate = Color(0xB3000000);

  /// Text and anything else that has to be read.
  static const Color onPlate = Color(0xFFFFFFFF);

  /// A control at rest, held back from the label beside it without going
  /// grey: about 5:1 over the worst-case plate, comfortably past the 3:1 a
  /// non-text control needs.
  static const Color onPlateSubdued = Color(0xB3FFFFFF);
}
