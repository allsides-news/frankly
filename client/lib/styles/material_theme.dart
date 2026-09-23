/// This is an auto-generated file from the Material 3
/// Plugin for Figma. The only thing that has been changed
/// is the util method toColorScheme, which only creates a very
/// limited palette by default and has been extended to fix that issue.
///
/// Gray/neutral color roles across all schemes have been remapped to the
/// nearest Tailwind CSS `neutral` scale value (neutral-50 through
/// neutral-950), as part of AllSides' migration of its UIs to that palette.
/// `error`/`errorContainer` roles and pure black/white were left unchanged
/// since they aren't part of the neutral scale.

import 'package:client/styles/app_styles.dart';
import 'package:flutter/material.dart';

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static MaterialScheme lightScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: AppNeutralColors.neutral800,
      surfaceTint: AppNeutralColors.neutral600,
      onPrimary: Color(0xffffffff),
      primaryContainer: AppNeutralColors.neutral700,
      onPrimaryContainer: AppNeutralColors.neutral300,
      secondary: AppNeutralColors.neutral600,
      onSecondary: Color(0xffffffff),
      secondaryContainer: AppNeutralColors.neutral200,
      onSecondaryContainer: AppNeutralColors.neutral700,
      tertiary: AppNeutralColors.neutral600,
      onTertiary: Color(0xffffffff),
      tertiaryContainer: AppNeutralColors.neutral300,
      onTertiaryContainer: AppNeutralColors.neutral700,
      error: Color(0xffa0000b),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffd92d29),
      onErrorContainer: Color(0xffffffff),
      surface: AppNeutralColors.neutral50,
      onSurface: AppNeutralColors.neutral900,
      onSurfaceVariant: AppNeutralColors.neutral700,
      outline: AppNeutralColors.neutral500,
      outlineVariant: AppNeutralColors.neutral300,
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: AppNeutralColors.neutral800,
      inverseOnSurface: AppNeutralColors.neutral100,
      inversePrimary: AppNeutralColors.neutral300,
      primaryFixed: AppNeutralColors.neutral200,
      onPrimaryFixed: AppNeutralColors.neutral900,
      primaryFixedDim: AppNeutralColors.neutral300,
      onPrimaryFixedVariant: AppNeutralColors.neutral700,
      secondaryFixed: AppNeutralColors.neutral200,
      onSecondaryFixed: AppNeutralColors.neutral900,
      secondaryFixedDim: AppNeutralColors.neutral300,
      onSecondaryFixedVariant: AppNeutralColors.neutral700,
      tertiaryFixed: AppNeutralColors.neutral200,
      onTertiaryFixed: AppNeutralColors.neutral900,
      tertiaryFixedDim: AppNeutralColors.neutral300,
      onTertiaryFixedVariant: AppNeutralColors.neutral700,
      surfaceDim: AppNeutralColors.neutral300,
      surfaceBright: AppNeutralColors.neutral50,
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: AppNeutralColors.neutral100,
      surfaceContainer: Color(0xffededed),
      surfaceContainerHigh: AppNeutralColors.neutral200,
      surfaceContainerHighest: Color(0xffdcdcdc),
    );
  }

  ThemeData light() {
    return theme(lightScheme().toColorScheme());
  }

  static MaterialScheme lightMediumContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: AppNeutralColors.neutral800,
      surfaceTint: AppNeutralColors.neutral600,
      onPrimary: Color(0xffffffff),
      primaryContainer: AppNeutralColors.neutral700,
      onPrimaryContainer: AppNeutralColors.neutral200,
      secondary: AppNeutralColors.neutral700,
      onSecondary: Color(0xffffffff),
      secondaryContainer: AppNeutralColors.neutral500,
      onSecondaryContainer: Color(0xffffffff),
      tertiary: AppNeutralColors.neutral700,
      onTertiary: Color(0xffffffff),
      tertiaryContainer: AppNeutralColors.neutral500,
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff8c0008),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffd92d29),
      onErrorContainer: Color(0xffffffff),
      surface: AppNeutralColors.neutral50,
      onSurface: AppNeutralColors.neutral900,
      onSurfaceVariant: AppNeutralColors.neutral700,
      outline: AppNeutralColors.neutral600,
      outlineVariant: AppNeutralColors.neutral500,
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: AppNeutralColors.neutral800,
      inverseOnSurface: AppNeutralColors.neutral100,
      inversePrimary: AppNeutralColors.neutral300,
      primaryFixed: AppNeutralColors.neutral500,
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: AppNeutralColors.neutral600,
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: AppNeutralColors.neutral500,
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: AppNeutralColors.neutral600,
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: AppNeutralColors.neutral500,
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: AppNeutralColors.neutral600,
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: AppNeutralColors.neutral300,
      surfaceBright: AppNeutralColors.neutral50,
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: AppNeutralColors.neutral100,
      surfaceContainer: Color(0xffededed),
      surfaceContainerHigh: AppNeutralColors.neutral200,
      surfaceContainerHighest: Color(0xffdcdcdc),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme().toColorScheme());
  }

  static MaterialScheme lightHighContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.light,
      primary: AppNeutralColors.neutral800,
      surfaceTint: AppNeutralColors.neutral600,
      onPrimary: Color(0xffffffff),
      primaryContainer: AppNeutralColors.neutral700,
      onPrimaryContainer: Color(0xffffffff),
      secondary: AppNeutralColors.neutral800,
      onSecondary: Color(0xffffffff),
      secondaryContainer: AppNeutralColors.neutral700,
      onSecondaryContainer: Color(0xffffffff),
      tertiary: AppNeutralColors.neutral800,
      onTertiary: Color(0xffffffff),
      tertiaryContainer: AppNeutralColors.neutral700,
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff4e0002),
      onError: Color(0xffffffff),
      errorContainer: Color(0xff8c0008),
      onErrorContainer: Color(0xffffffff),
      surface: AppNeutralColors.neutral50,
      onSurface: Color(0xff000000),
      onSurfaceVariant: AppNeutralColors.neutral800,
      outline: AppNeutralColors.neutral700,
      outlineVariant: AppNeutralColors.neutral700,
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: AppNeutralColors.neutral800,
      inverseOnSurface: Color(0xffffffff),
      inversePrimary: AppNeutralColors.neutral200,
      primaryFixed: AppNeutralColors.neutral700,
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: AppNeutralColors.neutral800,
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: AppNeutralColors.neutral700,
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: AppNeutralColors.neutral800,
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: AppNeutralColors.neutral700,
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: AppNeutralColors.neutral800,
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: AppNeutralColors.neutral300,
      surfaceBright: AppNeutralColors.neutral50,
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: AppNeutralColors.neutral100,
      surfaceContainer: Color(0xffededed),
      surfaceContainerHigh: AppNeutralColors.neutral200,
      surfaceContainerHighest: Color(0xffdcdcdc),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme().toColorScheme());
  }

  static MaterialScheme darkScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: AppNeutralColors.neutral300,
      surfaceTint: AppNeutralColors.neutral300,
      onPrimary: AppNeutralColors.neutral800,
      primaryContainer: AppNeutralColors.neutral800,
      onPrimaryContainer: AppNeutralColors.neutral400,
      secondary: Color(0xffffffff),
      onSecondary: AppNeutralColors.neutral800,
      secondaryContainer: AppNeutralColors.neutral300,
      onSecondaryContainer: AppNeutralColors.neutral700,
      tertiary: AppNeutralColors.neutral200,
      onTertiary: AppNeutralColors.neutral800,
      tertiaryContainer: AppNeutralColors.neutral400,
      onTertiaryContainer: AppNeutralColors.neutral800,
      error: Color(0xffffb4ab),
      onError: Color(0xff690004),
      errorContainer: Color(0xffb70f14),
      onErrorContainer: Color(0xffffffff),
      surface: AppNeutralColors.neutral800,
      onSurface: AppNeutralColors.neutral200,
      onSurfaceVariant: AppNeutralColors.neutral300,
      outline: AppNeutralColors.neutral400,
      outlineVariant: AppNeutralColors.neutral700,
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: AppNeutralColors.neutral200,
      inverseOnSurface: AppNeutralColors.neutral800,
      inversePrimary: AppNeutralColors.neutral600,
      primaryFixed: AppNeutralColors.neutral200,
      onPrimaryFixed: AppNeutralColors.neutral900,
      primaryFixedDim: AppNeutralColors.neutral300,
      onPrimaryFixedVariant: AppNeutralColors.neutral700,
      secondaryFixed: AppNeutralColors.neutral200,
      onSecondaryFixed: AppNeutralColors.neutral900,
      secondaryFixedDim: AppNeutralColors.neutral300,
      onSecondaryFixedVariant: AppNeutralColors.neutral700,
      tertiaryFixed: AppNeutralColors.neutral200,
      onTertiaryFixed: AppNeutralColors.neutral900,
      tertiaryFixedDim: AppNeutralColors.neutral300,
      onTertiaryFixedVariant: AppNeutralColors.neutral700,
      surfaceDim: AppNeutralColors.neutral900,
      surfaceBright: AppNeutralColors.neutral600,
      surfaceContainerLowest: AppNeutralColors.neutral900,
      surfaceContainerLow: AppNeutralColors.neutral900,
      surfaceContainer: AppNeutralColors.neutral800,
      surfaceContainerHigh: AppNeutralColors.neutral700,
      surfaceContainerHighest: AppNeutralColors.neutral700,
    );
  }

  ThemeData dark() {
    return theme(darkScheme().toColorScheme());
  }

  static MaterialScheme darkMediumContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: AppNeutralColors.neutral300,
      surfaceTint: AppNeutralColors.neutral300,
      onPrimary: AppNeutralColors.neutral900,
      primaryContainer: AppNeutralColors.neutral400,
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xffffffff),
      onSecondary: AppNeutralColors.neutral800,
      secondaryContainer: AppNeutralColors.neutral300,
      onSecondaryContainer: AppNeutralColors.neutral900,
      tertiary: AppNeutralColors.neutral200,
      onTertiary: AppNeutralColors.neutral800,
      tertiaryContainer: AppNeutralColors.neutral400,
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xffffbab1),
      onError: Color(0xff370001),
      errorContainer: Color(0xffff5449),
      onErrorContainer: Color(0xff000000),
      surface: AppNeutralColors.neutral900,
      onSurface: AppNeutralColors.neutral50,
      onSurfaceVariant: AppNeutralColors.neutral300,
      outline: AppNeutralColors.neutral400,
      outlineVariant: AppNeutralColors.neutral500,
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: AppNeutralColors.neutral200,
      inverseOnSurface: AppNeutralColors.neutral800,
      inversePrimary: AppNeutralColors.neutral700,
      primaryFixed: AppNeutralColors.neutral200,
      onPrimaryFixed: AppNeutralColors.neutral900,
      primaryFixedDim: AppNeutralColors.neutral300,
      onPrimaryFixedVariant: AppNeutralColors.neutral700,
      secondaryFixed: AppNeutralColors.neutral200,
      onSecondaryFixed: AppNeutralColors.neutral950,
      secondaryFixedDim: AppNeutralColors.neutral300,
      onSecondaryFixedVariant: AppNeutralColors.neutral700,
      tertiaryFixed: AppNeutralColors.neutral200,
      onTertiaryFixed: AppNeutralColors.neutral950,
      tertiaryFixedDim: AppNeutralColors.neutral300,
      onTertiaryFixedVariant: AppNeutralColors.neutral700,
      surfaceDim: Color(0xff121212),
      surfaceBright: AppNeutralColors.neutral600,
      surfaceContainerLowest: AppNeutralColors.neutral950,
      surfaceContainerLow: AppNeutralColors.neutral900,
      surfaceContainer: AppNeutralColors.neutral800,
      surfaceContainerHigh: Color(0xff333333),
      surfaceContainerHighest: AppNeutralColors.neutral700,
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme().toColorScheme());
  }

  static MaterialScheme darkHighContrastScheme() {
    return const MaterialScheme(
      brightness: Brightness.dark,
      primary: AppNeutralColors.neutral50,
      surfaceTint: AppNeutralColors.neutral300,
      onPrimary: Color(0xff000000),
      primaryContainer: AppNeutralColors.neutral300,
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xffffffff),
      onSecondary: Color(0xff000000),
      secondaryContainer: AppNeutralColors.neutral300,
      onSecondaryContainer: Color(0xff000000),
      tertiary: AppNeutralColors.neutral50,
      onTertiary: Color(0xff000000),
      tertiaryContainer: AppNeutralColors.neutral300,
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xfffff9f9),
      onError: Color(0xff000000),
      errorContainer: Color(0xffffbab1),
      onErrorContainer: Color(0xff000000),
      surface: AppNeutralColors.neutral900,
      onSurface: Color(0xffffffff),
      onSurfaceVariant: AppNeutralColors.neutral50,
      outline: AppNeutralColors.neutral300,
      outlineVariant: AppNeutralColors.neutral300,
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: AppNeutralColors.neutral200,
      inverseOnSurface: Color(0xff000000),
      inversePrimary: AppNeutralColors.neutral800,
      primaryFixed: AppNeutralColors.neutral200,
      onPrimaryFixed: Color(0xff000000),
      primaryFixedDim: AppNeutralColors.neutral300,
      onPrimaryFixedVariant: AppNeutralColors.neutral900,
      secondaryFixed: AppNeutralColors.neutral200,
      onSecondaryFixed: Color(0xff000000),
      secondaryFixedDim: AppNeutralColors.neutral300,
      onSecondaryFixedVariant: AppNeutralColors.neutral900,
      tertiaryFixed: AppNeutralColors.neutral200,
      onTertiaryFixed: Color(0xff000000),
      tertiaryFixedDim: AppNeutralColors.neutral300,
      onTertiaryFixedVariant: AppNeutralColors.neutral900,
      surfaceDim: Color(0xff121212),
      surfaceBright: AppNeutralColors.neutral600,
      surfaceContainerLowest: AppNeutralColors.neutral950,
      surfaceContainerLow: AppNeutralColors.neutral900,
      surfaceContainer: AppNeutralColors.neutral800,
      surfaceContainerHigh: Color(0xff333333),
      surfaceContainerHighest: AppNeutralColors.neutral700,
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme().toColorScheme());
  }

  ThemeData theme(ColorScheme colorScheme) => ThemeData(
        useMaterial3: true,
        brightness: colorScheme.brightness,
        colorScheme: colorScheme,
        textTheme: textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        ),
        scaffoldBackgroundColor: colorScheme.surface,
        canvasColor: colorScheme.surface,
      );

  List<ExtendedColor> get extendedColors => [];
}

class MaterialScheme {
  const MaterialScheme({
    required this.brightness,
    required this.primary,
    required this.surfaceTint,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.scrim,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.inversePrimary,
    required this.primaryFixed,
    required this.onPrimaryFixed,
    required this.primaryFixedDim,
    required this.onPrimaryFixedVariant,
    required this.secondaryFixed,
    required this.onSecondaryFixed,
    required this.secondaryFixedDim,
    required this.onSecondaryFixedVariant,
    required this.tertiaryFixed,
    required this.onTertiaryFixed,
    required this.tertiaryFixedDim,
    required this.onTertiaryFixedVariant,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
  });

  final Brightness brightness;
  final Color primary;
  final Color surfaceTint;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color shadow;
  final Color scrim;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color inversePrimary;
  final Color primaryFixed;
  final Color onPrimaryFixed;
  final Color primaryFixedDim;
  final Color onPrimaryFixedVariant;
  final Color secondaryFixed;
  final Color onSecondaryFixed;
  final Color secondaryFixedDim;
  final Color onSecondaryFixedVariant;
  final Color tertiaryFixed;
  final Color onTertiaryFixed;
  final Color tertiaryFixedDim;
  final Color onTertiaryFixedVariant;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
}

extension MaterialSchemeUtils on MaterialScheme {
  /// This util has been modified from the default export to include all colors
  /// in the ColorScheme class.
  ColorScheme toColorScheme() {
    return ColorScheme(
      // Carries the scheme's own brightness through. This was hardcoded to
      // `Brightness.light`, which meant every dark scheme produced a
      // ColorScheme claiming to be light -- so ThemeData (which takes its
      // brightness from the ColorScheme) built a light theme out of dark
      // colours, and every Material widget that branches on brightness got it
      // backwards.
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      primaryFixed: primaryFixed,
      primaryFixedDim: primaryFixedDim,
      onPrimaryFixed: onPrimaryFixed,
      onPrimaryFixedVariant: onPrimaryFixedVariant,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      secondaryFixed: secondaryFixed,
      secondaryFixedDim: secondaryFixedDim,
      onSecondaryFixed: onSecondaryFixed,
      onSecondaryFixedVariant: onSecondaryFixedVariant,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      tertiaryFixed: tertiaryFixed,
      tertiaryFixedDim: tertiaryFixedDim,
      onTertiaryFixed: onTertiaryFixed,
      onTertiaryFixedVariant: onTertiaryFixedVariant,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: surface,
      onSurface: onSurface,
      surfaceDim: surfaceDim,
      surfaceBright: surfaceBright,
      onSurfaceVariant: onSurfaceVariant,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      inverseSurface: inverseSurface,
      onInverseSurface: inverseOnSurface,
      inversePrimary: inversePrimary,
      outline: outline,
      outlineVariant: outlineVariant,
      scrim: scrim,
      shadow: shadow,
      surfaceTint: surfaceTint,
    );
  }
}

class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
