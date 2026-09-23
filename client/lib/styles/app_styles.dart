import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const List<Color> kOdometerColors = [
  Color.fromARGB(255, 181, 0, 0),
  Color.fromARGB(255, 190, 251, 155),
  Color.fromARGB(255, 155, 251, 227),
  Color.fromARGB(255, 136, 197, 255),
];

/// Tailwind CSS neutral gray scale (https://tailwindcss.com/docs/colors).
/// The raw Tailwind `neutral` scale.
///
/// These constants are absolute: `neutral800` is always dark. Reach for
/// [AppNeutralColors.of] instead wherever a shade was chosen for its
/// *relationship* to the background (body text, dividers, hover fills), so it
/// keeps that relationship in dark mode. Use the constants directly only when
/// a colour must not move -- a scrim over a photo, say, which is dark in both
/// modes because the photo behind it is.
/// Accents that have to hold their own colour in both themes.
///
/// These sit on grounds the theme doesn't control -- a participant's video, a
/// dialog's black54 barrier -- so a `colorScheme` token would flip underneath
/// them and a fixed value is the point, not an oversight.
class AppAccentColors {
  AppAccentColors._();

  /// Marks "this person" through the call: the ring on a speaking tile, the
  /// ring on a ready avatar, and the tutorial's pointer.
  static const Color violet = Color(0xFFA677D0);
}

class AppNeutralColors {
  AppNeutralColors._();

  /// A brightness-aware view of the scale, mirrored under a dark theme
  /// (50<->950, 100<->900, ... 500 is its own mirror).
  static AppNeutralPalette of(BuildContext context) =>
      AppNeutralPalette(Theme.of(context).brightness);

  static const neutral50 = Color(0xFFFAFAFA);
  static const neutral100 = Color(0xFFF5F5F5);
  static const neutral200 = Color(0xFFE5E5E5);
  static const neutral300 = Color(0xFFD4D4D4);
  static const neutral400 = Color(0xFFA3A3A3);
  static const neutral500 = Color(0xFF737373);
  static const neutral600 = Color(0xFF525252);
  static const neutral700 = Color(0xFF404040);
  static const neutral800 = Color(0xFF262626);
  static const neutral900 = Color(0xFF171717);
  static const neutral950 = Color(0xFF0A0A0A);
}

/// The Tailwind neutral scale, mirrored under a dark theme.
///
/// Picking `neutral300` for a divider means "a little darker than a light
/// background". Under a dark theme that intent is `neutral700`, so this
/// returns that -- the shade's role survives the mode switch, which a bare
/// constant cannot do.
class AppNeutralPalette {
  final Brightness brightness;

  const AppNeutralPalette(this.brightness);

  bool get _mirrored => brightness == Brightness.dark;

  Color get neutral50 =>
      _mirrored ? AppNeutralColors.neutral950 : AppNeutralColors.neutral50;
  Color get neutral100 =>
      _mirrored ? AppNeutralColors.neutral900 : AppNeutralColors.neutral100;
  Color get neutral200 =>
      _mirrored ? AppNeutralColors.neutral800 : AppNeutralColors.neutral200;
  Color get neutral300 =>
      _mirrored ? AppNeutralColors.neutral700 : AppNeutralColors.neutral300;
  Color get neutral400 =>
      _mirrored ? AppNeutralColors.neutral600 : AppNeutralColors.neutral400;

  /// The midpoint of the scale mirrors onto itself.
  Color get neutral500 => AppNeutralColors.neutral500;

  Color get neutral600 =>
      _mirrored ? AppNeutralColors.neutral400 : AppNeutralColors.neutral600;
  Color get neutral700 =>
      _mirrored ? AppNeutralColors.neutral300 : AppNeutralColors.neutral700;
  Color get neutral800 =>
      _mirrored ? AppNeutralColors.neutral200 : AppNeutralColors.neutral800;
  Color get neutral900 =>
      _mirrored ? AppNeutralColors.neutral100 : AppNeutralColors.neutral900;
  Color get neutral950 =>
      _mirrored ? AppNeutralColors.neutral50 : AppNeutralColors.neutral950;
}

/// Returns [style] with its font size increased by [delta], using
/// [defaultFontSize] if [style] (or its fontSize) is null.
TextStyle? bumpFontSize(
  TextStyle? style,
  double delta, {
  required double defaultFontSize,
}) =>
    style?.copyWith(fontSize: (style.fontSize ?? defaultFontSize) + delta);

/// Class that holds custom [TextStyle]s.
///
/// [height] is calculated by taking original [height] and dividing by [fontSize].
/// For example, Line Height in Figma is 20 and Font Size is 10.
/// [height] will become 20/10 => 2.
class AppTextStyle {
  static TextStyle headline1 = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      fontSize: 40,
      height: 1.1,
    ),
  );

  static TextStyle headline2 = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      fontSize: 30,
      height: 1.1,
    ),
  );

  static TextStyle headline2Light = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w300,
      fontStyle: FontStyle.normal,
      fontSize: 34,
      height: 1.1,
    ),
  );

  static TextStyle headline3 = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      fontSize: 24,
      height: 1.1,
    ),
  );

  static TextStyle headline4 = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      fontSize: 18,
      height: 1.2,
    ),
  );

  static TextStyle headlineSmall = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      fontSize: 12,
      height: 1.2,
    ),
  );

  static TextStyle subhead = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      fontSize: 18,
      height: 1.5,
    ),
  );

  static TextStyle eyebrow = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      fontSize: 16,
      height: 1.5,
    ),
  );

  static TextStyle eyebrowSmall = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      fontSize: 14,
      height: 1.5,
    ),
  );

  static TextStyle body = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      fontSize: 16,
      height: 1.5,
    ),
  );

  static TextStyle bodyMedium = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      fontSize: 16,
      height: 1.5,
    ),
  );

  static TextStyle bodySmall = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      fontSize: 14,
      height: 1,
    ),
  );

  static TextStyle timeLarge = GoogleFonts.geist(
    textStyle: TextStyle(
      fontWeight: FontWeight.w200,
      fontStyle: FontStyle.normal,
      fontSize: 126,
      height: 1.2,
    ),
  );
}

class AppSize {
  static const kMaxCarouselSize = 524.0;

  /// Gap a dialog keeps between itself and the screen edge.
  ///
  /// Several dialogs are raw containers shown through showCustomDialog rather
  /// than Dialog widgets, so nothing supplies insetPadding for them and a
  /// maxWidth wider than the phone simply filled it. This can't be applied
  /// inside showCustomDialog itself -- some callers use it for deliberately
  /// full-screen overlays, like the announcements hover menu.
  static const kDialogEdgeInset = 24.0;
  // Sized around the Space nav pill (48) plus 8px of breathing room above and
  // below it.
  static const kNavBarHeight = 64.0;

  /// Corner radius of a square image, as a share of its edge length, so it
  /// reads as the same shape at any size. A ratio of 0.5 would be a circle,
  /// which is reserved for user profile images.
  ///
  /// Space logos are the rounder of the two; Event and Template images are
  /// deliberately squarer, so the two kinds stay distinguishable at a glance.
  static const kSpaceLogoRadiusRatio = 0.28;
  static const kEventImageRadiusRatio = 0.18;
  static const kBottomNavBarHeight = 75.0;
  static const kSidebarWidth = 376.0;

  static const kPageContentMaxWidthDesktop = 1100.0;
  static const kHomeContentMaxWidthMobile = 550.0;

  static const kHomePageCommunityIconSize = 32.0;
}

class AppDecoration {
  static const BoxShadow lightBoxShadow = BoxShadow(
    blurRadius: 6,
    offset: Offset(2, 2),
    color: Color.fromARGB(82, 0, 0, 0),
  );
}
