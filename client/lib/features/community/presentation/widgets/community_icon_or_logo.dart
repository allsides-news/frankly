import 'package:client/core/utils/image_utils.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:data_models/community/community.dart';
import 'package:provider/provider.dart';

/// This widget either shows the app icon or a logo of the selected community, if one is selected.
class CurrentCommunityIconOrLogo extends StatelessWidget {
  /// If true, this widget is a button that navigates either to the app's website or the community's landing page
  final bool withNav;
  final bool darkLogo;
  final Community? community;

  const CurrentCommunityIconOrLogo({
    this.withNav = true,
    this.community,
    this.darkLogo = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentCommunity =
        Provider.of<NavBarProvider>(context).currentCommunity ?? community;
    final showOrganizationIcon =
        routerDelegate.currentBeamLocation is! HomeLocation;
    final isMobile = responsiveLayoutService.isMobile(context);

    if (currentCommunity != null && withNav && showOrganizationIcon) {
      // Display-only: this is not a link back to "My Spaces", just the
      // Space's logo shown for context. No hover/cursor/tap affordances.
      return CommunityCircleIcon(
        currentCommunity,
        withBorder: isMobile,
        isTooltipShown: false,
        backgroundColor: Colors.transparent,
      );
    } else if (withNav) {
      return _HoverableLogoButton(
        onTap: () => routerDelegate.beamTo(HomeLocation()),
        child: _buildLogo(context: context, isMobile: isMobile),
      );
    } else if (currentCommunity != null) {
      return CommunityCircleIcon(
        currentCommunity,
        withBorder: isMobile,
        isTooltipShown: false,
        backgroundColor: Colors.transparent,
      );
    } else {
      return _buildLogo(context: context, isMobile: isMobile);
    }
  }

  Widget _buildLogo({required BuildContext context, required bool isMobile}) {
    // Aspect ratio (361:51) preserved from the source wordmark asset.
    final height = isMobile ? 25.0 : 34.0;
    final width = height * 361 / 51;

    return Semantics(
      label: context.l10n.franklyLogo,
      child: Image.asset(
        AppAsset.kLogoRoundtablesPng.path,
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// A plain-rectangle, no-padding tap target that overlays [child] with flat
/// white at 50% opacity on hover. Used instead of [IconButton], whose ink
/// region is sized around square icon content and doesn't track a much
/// wider custom child like a wordmark image.
class _HoverableLogoButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _HoverableLogoButton({required this.onTap, required this.child});

  @override
  State<_HoverableLogoButton> createState() => _HoverableLogoButtonState();
}

class _HoverableLogoButtonState extends State<_HoverableLogoButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _isHovered ? Colors.white.withOpacity(0.5) : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A Space's logo.
///
/// Always a rounded square -- circles are reserved for user profile images, so
/// the two are never confusable at a glance.
class CommunityCircleIcon extends StatelessWidget {
  final bool withBorder;
  final Community community;
  final double imageHeight;
  final bool isTooltipShown;
  final Color? backgroundColor;

  /// Corner radius in logical pixels. Defaults to a share of [imageHeight] so
  /// the logo reads as a rounded square at any size -- note that a radius of
  /// half [imageHeight] would render a circle, so keep this well under that.
  final double? borderRadius;

  const CommunityCircleIcon(
    this.community, {
    this.withBorder = false,
    this.imageHeight = 42,
    this.isTooltipShown = true,
    this.backgroundColor,
    this.borderRadius,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String? profileImageUrl = community.profileImageUrl;
    if (profileImageUrl == null || profileImageUrl.isEmpty) {
      profileImageUrl =
          generateRandomImageUrl(seed: community.id.hashCode, resolution: 160);
    }

    final radius =
        BorderRadius.circular(borderRadius ?? imageHeight * AppSize.kSpaceLogoRadiusRatio);

    final child = Container(
      decoration: BoxDecoration(
        border: withBorder
            ? Border.all(
                color: context.theme.colorScheme.onPrimaryContainer,
                width: 1,
              )
            : null,
        borderRadius: radius,
        color: backgroundColor ?? context.theme.colorScheme.onPrimaryContainer,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ProxiedImage(
          profileImageUrl,
          height: imageHeight,
          width: imageHeight,
          fit: BoxFit.cover,
        ),
      ),
    );

    if (isTooltipShown) {
      return Tooltip(
        message: community.name ?? '',
        child: child,
      );
    } else {
      return child;
    }
  }
}
