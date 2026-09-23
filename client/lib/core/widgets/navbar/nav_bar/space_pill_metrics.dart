/// Metrics for the Space nav pill in [NavBar].
///
/// [Container] paints [kSpacePillBorderWidth] inside [kSpacePillHeight], so
/// the height must include the border. Inner content height is [kSpaceLogoSize].

/// Space logo edge length, and the pill's inner content height.
const double kSpaceLogoSize = 36.0;

/// Internal padding of the Space nav pill, equal on all four sides.
const double kSpacePillPadding = 4.0;

/// Hairline around the pill.
const double kSpacePillBorderWidth = 1.0;

/// Corner radius of the Space nav pill.
const double kSpacePillRadius = 16.0;

/// Corner radius of the Space logo -- the pill's radius less the gap between
/// them, so the two curves stay concentric.
const double kSpaceLogoRadius = kSpacePillRadius - kSpacePillPadding;

/// Outer pill height: logo, padding, and the 1px border on top and bottom.
const double kSpacePillHeight = kSpaceLogoSize +
    kSpacePillPadding * 2 +
    kSpacePillBorderWidth * 2;

/// Size of the section icons (and the bell) inside the pill on mobile.
const double kSpacePillIconSize = 24.0;

/// Gap between the Space logo and the first section icon.
const double kSpacePillLogoGap = 6.0;

/// Minimum breathing room between the pill and the top/bottom of the nav.
const double kSpacePillMargin = 4.0;
