import 'package:client/styles/app_asset.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/constrained_body.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/community/utils/community_theme_utils.dart.dart';
import 'package:client/features/community/presentation/widgets/community_icon_or_logo.dart';
import 'package:client/features/community/presentation/widgets/community_membership_button.dart';
import 'package:client/features/community/presentation/widgets/edit_community_button.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:data_models/community/community.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Width-to-height ratio of the Space banner. Applied at every screen size, so
/// the banner scales with the viewport rather than jumping between fixed
/// heights.
const double kSpaceBannerAspectRatio = 4.0;

/// Corner radius of the banner on desktop, where it sits inset from the page
/// edges. Mobile runs it full-bleed with square corners instead.
const double kSpaceBannerRadius = 12.0;

/// Gap between the nav bar and the top of the banner.
const double kSpaceHeaderTopGap = 32.0;

const double kSpaceHeaderLogoDesktop = 112.0;
const double kSpaceHeaderLogoMobile = 72.0;

/// White ring around the Space logo, separating it from the banner behind it.
const double kSpaceHeaderLogoRing = 4.0;

/// How much of the logo sits on top of the banner, as a share of its height --
/// the rest hangs below into the title row.
const double kSpaceHeaderLogoOverlap = 0.4;

/// The banner, the owner actions over its top-right corner, the Space logo
/// straddling its bottom-left corner, and the Space name.
class SpacePageHeader extends StatelessWidget {
  final Community community;

  const SpacePageHeader({required this.community, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isMobile = responsiveLayoutService.isMobile(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBannerAndTitle(context, isMobile: isMobile),
        Divider(height: 1, color: AppNeutralColors.of(context).neutral300),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mobile runs the banner full-bleed and flush to the nav; desktop
        // insets it and keeps both banner and divider inside the page content
        // bounds.
        if (isMobile)
          content
        else ...[
          SizedBox(height: kSpaceHeaderTopGap),
          ConstrainedBody(child: content),
        ],
      ],
    );
  }

  Widget _buildBannerAndTitle(BuildContext context, {required bool isMobile}) {
    final logoSize = isMobile ? kSpaceHeaderLogoMobile : kSpaceHeaderLogoDesktop;
    final ringedLogoSize = logoSize + kSpaceHeaderLogoRing * 2;
    final overlap = ringedLogoSize * kSpaceHeaderLogoOverlap;
    final logoInset = isMobile ? 16.0 : 24.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The banner's height follows from the available width, which is what
        // lets the logo be positioned against its bottom edge exactly.
        final bannerHeight = constraints.maxWidth / kSpaceBannerAspectRatio;

        return Stack(
          // The logo deliberately hangs outside the banner's bounds.
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: bannerHeight,
                  child: _buildBanner(context, isMobile: isMobile),
                ),
                ConstrainedBox(
                  // At minimum, tall enough to clear the part of the logo
                  // hanging below the banner; grows if the title wraps.
                  constraints: BoxConstraints(
                    minHeight: ringedLogoSize - overlap + 20,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: logoInset + ringedLogoSize + 16,
                      right: isMobile ? 16 : 0,
                      top: 8,
                      bottom: 12,
                    ),
                    child: _buildTitleRow(context, isMobile: isMobile),
                  ),
                ),
              ],
            ),
            Positioned(
              left: logoInset,
              top: bannerHeight - overlap,
              child: _buildRingedLogo(context, logoSize: logoSize),
            ),
            // Owner actions sit over the banner's top-right corner, clear of
            // the logo and the title.
            Positioned(
              top: 16,
              right: 16,
              child: _buildOwnerActions(context),
            ),
          ],
        );
      },
    );
  }

  /// The Space logo on a ring the colour of the page behind it, so the logo
  /// reads as punched out of the page rather than sitting on a white chip.
  ///
  /// Resolved the same way CustomScaffold picks its bgColor -- the Space's
  /// brand background when it has one, the theme surface otherwise -- so the
  /// ring keeps matching under a dark theme and under custom Space colours.
  Widget _buildRingedLogo(BuildContext context, {required double logoSize}) {
    final logoRadius = logoSize * 0.28;
    final pageBackground = SpaceBrandColors.resolve(
          lightColor: community.themeLightColor,
          darkColor: community.themeDarkColor,
          brightness: Theme.of(context).brightness,
        )?.background ??
        context.theme.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(kSpaceHeaderLogoRing),
      decoration: BoxDecoration(
        color: pageBackground,
        borderRadius: BorderRadius.circular(logoRadius + kSpaceHeaderLogoRing),
      ),
      child: CommunityCircleIcon(
        community,
        imageHeight: logoSize,
        borderRadius: logoRadius,
        isTooltipShown: false,
        backgroundColor: Colors.transparent,
      ),
    );
  }

  Widget _buildBanner(BuildContext context, {required bool isMobile}) {
    // A Space with no banner gets the placeholder artwork rather than a random
    // stock photo, which read as a real choice the Space had made.
    final banner = isNullOrEmpty(community.bannerImageUrl)
        ? SvgPicture.asset(AppAsset.kBannerEmptySvg.path, fit: BoxFit.cover)
        : ProxiedImage(community.bannerImageUrl, fit: BoxFit.cover);

    if (isMobile) return banner;

    return ClipRRect(
      borderRadius: BorderRadius.circular(kSpaceBannerRadius),
      child: banner,
    );
  }

  /// Edit and Space Admin, on the same visibility rule the nav bar used for
  /// the admin gear: an admin, viewing their own Space.
  Widget _buildOwnerActions(BuildContext context) {
    final canEdit =
        Provider.of<CommunityPermissionsProvider>(context).canEditCommunity;
    if (!canEdit) return SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EditCommunityButton(),
        SizedBox(width: 12),
        // Mirrors EditCommunityButton's treatment -- both need to stay legible
        // over an arbitrary banner image, so both are filled rather than bare
        // glyphs.
        IconButton.filled(
          icon: Icon(
            Icons.settings_outlined,
            color: context.theme.colorScheme.onSecondary,
          ),
          visualDensity: VisualDensity.compact,
          iconSize: 24,
          color: context.theme.colorScheme.secondary,
          tooltip: 'Space admin',
          onPressed: () => routerDelegate.beamTo(
            CommunityPageRoutes(communityDisplayId: community.displayId)
                .communityAdmin(),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context, {required bool isMobile}) {
    final isMember = userDataService.isMember(communityId: community.id);

    final tagLine = community.tagLine;

    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        HeightConstrainedText(
          community.name ?? '',
          style: GoogleFonts.geist(
            textStyle: context.theme.textTheme.headlineSmall,
            fontWeight: FontWeight.w700,
            fontSize: isMobile ? 22 : 28,
          ),
        ),
        if (!isNullOrEmpty(tagLine)) ...[
          SizedBox(height: 6),
          HeightConstrainedText(
            tagLine!,
            // onSurfaceVariant, not secondary: the Space child theme overrides
            // only primary and secondary, so this one stays legible.
            style: context.theme.textTheme.bodyLarge?.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final follow = isMember
        ? null
        : CommunityMembershipButton(community, height: 40, minWidth: 96);

    if (isMobile) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          name,
          if (follow != null) follow,
        ],
      );
    }

    return Row(
      children: [
        // Expanded, not Flexible-beside-a-Spacer: the title should use all the
        // width the Follow button doesn't need.
        Expanded(child: name),
        if (follow != null) ...[
          SizedBox(width: 16),
          follow,
        ],
      ],
    );
  }
}
