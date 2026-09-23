# 🎨 Theming and dark mode

The client ships a light and a dark theme and follows the OS setting
(`ThemeMode.system`). Every colour a widget draws should come from the active
`ColorScheme`, so the same widget works in both modes without knowing which one
it is in.

Most dark-mode bugs found so far were not "someone forgot dark mode". They were
a **colour pair that stops being a pair** — a fill and the content on top of it
sourced from tokens that move independently, or in lockstep. This page is mostly
about recognising that shape.

## Where things live

| Thing | File |
| --- | --- |
| The two `ColorScheme`s | `client/lib/styles/material_theme.dart` |
| Raw neutral ramp + `AppNeutralColors` | `client/lib/styles/app_styles.dart` |
| `ThemeData` assembly | `client/lib/styles/theme.dart` |
| `themeMode` wiring | `client/lib/app.dart` |
| Space brand colours | `client/lib/features/community/utils/community_theme_utils.dart.dart` |

## Picking a colour

Reach for a `colorScheme` role, and take **both halves of the pair** when you
draw content on a fill:

| You are drawing | Use |
| --- | --- |
| Page / sheet background | `surface`, `surfaceContainer*` |
| Body text, icons on a surface | `onSurface`, `onSurfaceVariant` |
| A filled primary button | `primary` fill + `onPrimary` label |
| A filled container / chip | `primaryContainer` + `onPrimaryContainer` |
| Outline button text and border | `primary` |
| Hairlines, dividers, muted glyphs | `outline`, `outlineVariant` |

`AppNeutralColors.<n>` are the **raw** ramp values — fixed, never theme-aware.
`AppNeutralColors.of(context).<n>` returns a *mirrored* palette: under a dark
theme `neutral50` yields `neutral950`, `neutral300` yields `neutral700`, and so
on, with `neutral500` mirroring onto itself. Use the mirrored form for
decoration that should flip with the theme (a hairline border), and the raw form
only when a value must stay put in both modes (see "Constant surfaces" below).

## The failure patterns

These have each caused at least one shipped bug. They are worth scanning for in
review.

### 1. Self-cancelling pairs

A fill and the content on it drawn from tokens that flip *together*, so they
stay the same distance apart — which can be zero.

```dart
// Both resolve to neutral800 under the dark theme: an invisible button
// with an invisible label.
ActionButton(color: someTokenThatEqualsOnPrimary, ...)
```

A filled `ActionButton` with no `color:` already fills with `primary`, so
passing `textColor: colorScheme.primary` paints the label onto its own
background. Leave `textColor` off and let it default to `onPrimary`.

### 2. Overriding half a pair

`community_page.dart` builds a `childTheme` for Spaces with custom brand
colours. Overriding `primary` **without** `onPrimary` breaks the pairing for
everything in that subtree — a `primary` fill keeps pulling the app's default
`onPrimary`, which has no relationship to the brand colour. Override both halves
together. The two brand colours are validated against each other at 4.5:1, so
each is a legitimate foreground for the other.

### 3. Theme tokens over a surface that isn't one

The recurring version of this is `colorScheme.scrim.withScrimOpacity`, which is
`withAlpha(82)` — black at 32%. That isn't a colour, it's a wash: the result
depends entirely on what happens to be behind it. Over the light panel it lands
near `#A9A9A9`; over the dark one, near `#1A1A1A`. No single foreground can sit
on both, so a token foreground over it is guaranteed to fail in one mode and
usually fails in both.

Work out which kind of surface you actually have:

**It's really the panel underneath.** Then don't wash it — give it a real
surface token and pair the foreground with it. The breakout room tiles and the
`Add Room` tile do this now: `surfaceContainerHighest` / `onSurface` for a
normal tile, `surfaceContainerLowest` for one that's picked out. Both clear 8:1
in both modes.

**It's arbitrary — someone's video.** Then no token can help, because the
ground changes frame to frame. Use `VideoOverlayColors` (`video/presentation/
widgets/video_overlay_colors.dart`): a plate opaque enough that white clears
4.5:1 over the brightest frame a camera can produce, plus the two foregrounds
that go on it. The name plate, the options dots, the muted-mic plate and the
recording badge all draw from it. Add to it rather than inventing another
constant next to it.

Do **not** reach for `onPrimaryContainer` as a "light in both schemes"
fallback. It's `neutral300` in light and `neutral400` in dark — a mid-grey
either way, which is how the participant name on a video tile ended up washed
out in both modes at once.

### 4. `ThemeData.primaryColor`

**Retired — do not reintroduce it.** It resolves to `colorScheme.primary` in
light but `colorScheme.surface` in dark (`theme_data.dart`), i.e. a foreground
in one mode and a background in the other. Everything that used it was written
when the app was light-only and meant `colorScheme.primary`.

### 5. Validating stored values against live tokens

A Space's brand colours are stored once and shown to every visitor in whichever
mode *they* use. Validating them against `colorScheme.*` gives different answers
depending on the admin's own theme — this is why `#ffffff` was once rejected as
"must be lighter". The colour picker compares against the fixed
`ThemeUtils.kLightColorReference` / `kDarkColorReference` instead.

### 6. Colour baked into a raster asset

A PNG's colour cannot follow the theme. Prefer a Material icon; failing that, a
single-fill SVG tinted with `ColorFilter.mode(colour, BlendMode.srcIn)` — see
`media/hostless.svg` and its use in `event_info.dart`.

## Space brand colours

A Space stores two colours, and the picker enforces that the light one is
lighter and that the two meet 4.5:1. `SpaceBrandColors.resolve` turns that pair
into a background/foreground for a given `Brightness`, swapping which is which
under a dark theme — so the contrast the admin chose holds in both modes.

Empty states: a Space with no banner gets `media/banner-empty.svg`
(`AppAsset.kBannerEmptySvg`), drawn at 4:1 to match `kSpaceBannerAspectRatio`.
Its greys are translucent so it settles over either theme's background. It
deliberately is *not* a random stock photo — that read as a real choice the
Space had made.

## Mobile live-meeting layout

`live_meeting_mobile_page.dart` has a few invariants that are easy to undo:

- The agenda panel has four states (`fullyVisible`, `partiallyVisible`, `peek`,
  `hidden`). `peek` is the resting state whenever the event has an agenda — the
  panel never fully dismisses, so the bottom bar never needs a button to bring
  it back. `hidden` is only for events with no agenda at all.
- In the `Stack` layout the parent owns the panel's height, so dragging tracks
  the finger. The `fullyVisible` layout uses `Expanded`, where there is no
  height to give it, and falls back to reading the swipe direction on release.
  The handle becomes a chevron there to signal tap-to-collapse.
- Which video layout you see is the viewer's choice via the top-bar toggle. It
  used to be inferred from how far the panel was open, which meant dragging the
  panel silently changed what you were watching.
- The top bar grows an overflow menu whenever the bottom bar is absent. That
  menu is the only route to Admin, and without it an admin in the waiting room
  had no way out.

## Two traps that are not about colour

- **`ActionButton` wraps its button in a `Row(mainAxisSize: min)`**, and
  `expand: true` puts an `Expanded` inside *that* Row, so it fills the width
  the caller gives it. Don't also wrap the call site in a tight-width box: the
  internal Row stretches to fill it, the button does not, and the Row's default
  `start` alignment leaves the button hugging the left edge. Give it `expand`
  or a width, not both.
- **CI does not run `flutter analyze`.** `test_client.yaml` runs only
  `flutter test`, so analyzer errors — including lints `analysis_options.yaml`
  escalates to `error`, such as `unawaited_futures` — reach `main` unnoticed.
  Run `fvm flutter analyze` locally before pushing.
