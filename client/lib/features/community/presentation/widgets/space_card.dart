import 'package:client/core/routing/locations.dart';
import 'package:client/core/utils/date_utils.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/stream_utils.dart';
import 'package:client/features/community/presentation/widgets/community_icon_or_logo.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/styles/styles.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/events/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

/// One Space, as a card: banner, logo, name, and when it next meets.
///
/// Shared by every list of Spaces on the home page so they stay identical --
/// the sections differ in which Spaces they show, not in how a Space looks.
class SpaceCard extends StatelessWidget {
  final Community community;

  const SpaceCard({required this.community, Key? key}) : super(key: key);

  static const double width = 295;

  /// Banner strip across the card's top. Roughly a third of the card, so the
  /// image reads as a header rather than the whole card.
  static const double bannerHeight = 96;
  static const double radius = 10;

  /// Every card is this tall regardless of how long its title is, so a row of
  /// them lines up. Enough for a two-line title; a shorter one just leaves
  /// space at the foot of the card.
  static const double height = 184;

  /// Gap between cards in a row.
  static const double gutter = 20;

  static const double _titleFontSize = 16;
  static const double _titleLineHeight = 1.3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomInkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => routerDelegate.beamTo(
          CommunityPageRoutes(
            communityDisplayId: community.displayId,
          ).communityHome,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: AppNeutralColors.of(context).neutral300,
              width: 1,
            ),
            color: context.theme.colorScheme.surfaceContainerLowest,
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: bannerHeight, child: _buildBanner()),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CommunityCircleIcon(
                      community,
                      imageHeight: 36,
                      isTooltipShown: false,
                      backgroundColor: Colors.transparent,
                    ),
                    SizedBox(width: 10),
                    Expanded(child: _buildDetails(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Space's banner. No scrim: nothing is overlaid on the image, so it
  /// doesn't need darkening.
  ///
  /// Falls back to the same placeholder artwork the Space page header uses, so
  /// a Space looks the same in both places.
  Widget _buildBanner() {
    if (isNullOrEmpty(community.bannerImageUrl)) {
      return SvgPicture.asset(AppAsset.kBannerEmptySvg.path, fit: BoxFit.cover);
    }
    return ProxiedImage(community.bannerImageUrl, fit: BoxFit.cover);
  }

  Widget _buildDetails(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The title takes only the lines it needs, so the activity line sits
        // directly under a one-line name. The card's own height is fixed, so
        // a shorter title leaves space at the foot of the card rather than
        // shortening it, and a row of cards still lines up.
        Text(
          community.name ?? 'Unnamed Space',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.theme.textTheme.titleMedium?.copyWith(
            fontSize: _titleFontSize,
            height: _titleLineHeight,
            fontWeight: FontWeight.w600,
            color: context.theme.colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 2),
        _buildNextEventLine(context),
      ],
    );
  }

  /// A sign that the Space is actually active, which a follower count can't
  /// give -- a Space with many followers may have nothing scheduled.
  Widget _buildNextEventLine(BuildContext context) {
    final style = context.theme.textTheme.bodySmall?.copyWith(
      color: context.theme.colorScheme.onSurfaceVariant,
    );

    return MemoizedStreamBuilder<Event?>(
      keys: [community.id],
      showLoading: false,
      streamGetter: () => firestoreEventService
          .nextActiveEventForCommunity(
            communityId: community.id,
            // Same rule the Space page uses: members see their Space's
            // private events, so a private event still counts as activity.
            includePrivateEvents:
                userDataService.getMembership(community.id).status?.isMember ??
                    false,
          )
          .asStream(),
      builder: (context, event) {
        final scheduled = event?.scheduledTime;
        if (scheduled == null) {
          return HeightConstrainedText('No upcoming events', style: style);
        }
        return HeightConstrainedText(
          // Same compact time form the event cards use.
          'Next: ${DateFormat('MMM d').format(scheduled)}, '
          '${eventTimeFormat(scheduled)}',
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
