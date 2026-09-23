import 'dart:async';

import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/features/home/presentation/widgets/section_heading_row.dart';
import 'package:client/features/community/presentation/widgets/space_card.dart';
import 'package:client/services.dart';
import 'package:data_models/community/community.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Spaces surfaced to everyone on the home page, whether or not they follow
/// them.
///
/// The list is hard-coded on purpose, and is meant to be temporary. There's no
/// "featured" concept on a Space -- the existing `featured` collection holds
/// templates and events *within* a Space, not Spaces themselves -- and adding
/// one is a schema change plus a query and an index. This gets a reliable
/// route to an event series onto the home page today, in one place that a real
/// `isFeatured` field can later replace.
///
/// Slugs rather than document ids: they're readable, they're what the Space
/// URLs use (`/space/allsides-roundtables`), and `communityStream` looks a
/// Space up by them.
const List<String> kFeaturedSpaceSlugs = ['allsides-roundtables'];

class FeaturedSpacesSection extends StatefulWidget {
  const FeaturedSpacesSection({Key? key}) : super(key: key);

  @override
  State<FeaturedSpacesSection> createState() => _FeaturedSpacesSectionState();
}

class _FeaturedSpacesSectionState extends State<FeaturedSpacesSection> {
  /// Space between this section and the Spaces you follow, which sits beside
  /// it on desktop. Kept here rather than at the call site so that a section
  /// with nothing to show takes up no room at all.
  static const double _desktopTrailingGap = 40;

  /// The home page's own left and right margins on mobile.
  static const double _mobileMargin = 20;

  /// Held for the section's lifetime rather than built in [build]: each one
  /// wraps a live Firestore listener, so building them per frame would leak a
  /// subscription on every rebuild.
  final List<BehaviorSubjectWrapper<Community>> _streams = [];
  final List<StreamSubscription<Community>> _subscriptions = [];

  /// Resolved Spaces, in the order they're listed above.
  ///
  /// A slug that fails to resolve stays null and is simply left out. That's
  /// deliberate: the whole section is hard-coded, so a Space that has been
  /// renamed or removed is a mistake in this file, not something the reader
  /// can act on -- better a missing card than an error where a card was.
  late final List<Community?> _communities =
      List<Community?>.filled(kFeaturedSpaceSlugs.length, null);

  @override
  void initState() {
    super.initState();

    for (var i = 0; i < kFeaturedSpaceSlugs.length; i++) {
      final index = i;
      final stream = firestoreDatabase.communityStream(kFeaturedSpaceSlugs[i]);
      _streams.add(stream);
      _subscriptions.add(
        stream.stream.listen(
          (community) => _set(index, community),
          onError: (_) => _set(index, null),
        ),
      );
    }
  }

  void _set(int index, Community? community) {
    if (!mounted || _communities[index] == community) return;
    setState(() => _communities[index] = community);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final stream in _streams) {
      stream.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final communities = _communities.whereType<Community>().toList();
    // No heading over an empty row, and nothing at all while the Spaces are
    // still loading -- the section appears once it has something to show.
    if (communities.isEmpty) return const SizedBox.shrink();

    final isMobile = responsiveLayoutService.isMobile(context);

    return Padding(
      padding: EdgeInsets.only(right: isMobile ? 0 : _desktopTrailingGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: isMobile ? _mobileMargin : 0),
            child: SectionHeadingRow('Featured'),
          ),
          SizedBox(height: 20),
          if (isMobile) _buildCarousel(communities) else _buildRow(communities),
        ],
      ),
    );
  }

  /// Desktop: the cards laid out at their own width, so the section hugs them
  /// and the Spaces you follow can sit alongside in the remaining space.
  Widget _buildRow(List<Community> communities) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final community in communities) ...[
          if (community != communities.first) SizedBox(width: SpaceCard.gutter),
          SpaceCard(community: community),
        ],
      ],
    );
  }

  /// Mobile: full width and scrolling, since two cards already overflow a
  /// phone.
  ///
  /// The width is set explicitly. Left to size itself, a single card wouldn't
  /// fill the row, and the centred column above would leave it floating in
  /// from the margin instead of aligned under the heading.
  Widget _buildCarousel(List<Community> communities) {
    return SizedBox(
      width: double.infinity,
      height: SpaceCard.height,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: _mobileMargin),
          dragStartBehavior: DragStartBehavior.down,
          physics: ClampingScrollPhysics(),
          // The card plus the gap that follows it, matching the Spaces
          // carousel below.
          itemExtent: SpaceCard.width + SpaceCard.gutter,
          scrollDirection: Axis.horizontal,
          itemCount: communities.length,
          // itemExtent constrains the child to card + gutter, so the Row keeps
          // the card at its own width and the rest becomes the gap.
          itemBuilder: (_, index) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpaceCard(community: communities[index]),
              SizedBox(width: SpaceCard.gutter),
            ],
          ),
        ),
      ),
    );
  }
}
