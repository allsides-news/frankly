import 'package:client/core/widgets/section_heading.dart';
import 'dart:math';

import 'package:client/features/auth/utils/auth_utils.dart';
import 'package:client/core/widgets/constrained_body.dart';
import 'package:flutter/material.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/events/features/create_event/presentation/views/create_event_dialog.dart';
import 'package:client/features/community/presentation/widgets/about_section.dart';
import 'package:client/features/community/presentation/widgets/event_card.dart';
import 'package:client/features/community/presentation/widgets/space_page_header.dart';
import 'package:client/features/community/data/providers/community_home_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/features/community/presentation/views/app_share.dart';
import 'package:client/features/community/presentation/widgets/share_section.dart';
import 'package:client/features/community/presentation/widgets/donate_widget.dart';
import 'package:client/core/widgets/empty_page_content.dart';
import 'package:client/features/community/presentation/widgets/community_membership_button.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/widgets/buttons/thick_outline_button.dart';
import 'package:client/config/environment.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/widgets/stream_utils.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/utils/share_type.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/community/community.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:client/core/widgets/pulse_loading_placeholder.dart';
import 'package:client/core/widgets/delayed_loading_placeholder.dart';

class CommunityHome extends StatefulWidget {
  const CommunityHome._();

  static Widget create() {
    return ChangeNotifierProvider(
      create: (context) => CommunityHomeProvider(
        communityProvider: context.read<CommunityProvider>(),
      ),
      child: CommunityHome._(),
    );
  }

  @override
  _CommunityHomeState createState() => _CommunityHomeState();
}

class _CommunityHomeState extends State<CommunityHome> {
  int _eventsToShow = 20;
  final int _eventCountIncrement = 5;

  Community get community => Provider.of<CommunityProvider>(context).community;

  @override
  void initState() {
    context.read<CommunityHomeProvider>().initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      analytics.logPageView(
        'community_home',
        communityId: context.read<CommunityProvider>().community.id,
      );
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MemoizedStreamBuilder<bool>(
        streamGetter: () =>
            context.read<CommunityProvider>().donationsEnabled().asStream(),
        keys: [community.id],
        builder: (context, showDonations) => Column(
          children: [
            SpacePageHeader(community: community),
            if (responsiveLayoutService.isMobile(context))
              ..._mobileLayout(showDonations!)
            else
              ..._desktopLayout(showDonations!),
          ],
        ),
      ),
    );
  }

  List<Widget> _mobileLayout(bool showDonations) => [
        ConstrainedBody(
          maxWidth: 524,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 30),
              _buildUpcoming(),
              SizedBox(height: 30),
              _buildAbout(showDonations),
              SizedBox(height: 30),
            ],
          ),
        ),
      ];

  List<Widget> _desktopLayout(bool showDonations) => [
        SizedBox(height: 30),
        ConstrainedBody(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const columnGap = 52.0;
              final columnWidth = (constraints.maxWidth - columnGap) / 2;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Upcoming leads on the left; About sits alongside it.
                  SizedBox(
                    width: columnWidth,
                    child: _buildUpcoming(),
                  ),
                  SizedBox(width: columnGap),
                  SizedBox(
                    width: columnWidth,
                    child: _buildAbout(showDonations),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: 100),
      ];

  Widget _buildUpcoming() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Upcoming'),
        SizedBox(height: 16),
        _buildEvents(),
      ],
    );
  }

  Widget _buildAbout(bool showDonations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityHomeAboutSection(community: community),
        SizedBox(height: 20),
        _buildContactUsSection(showDonations),
      ],
    );
  }

  Widget _buildEngagementButtons(bool showDonation) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        children: [
          if (!userDataService.isMember(communityId: community.id)) ...[
            CommunityMembershipButton(
              community,
            ),
            SizedBox(width: 12),
          ],
          if (showDonation)
            ThickOutlineButton(
              text: context.l10n.donate,
              eventName: 'donate_pressed',
              backgroundColor: Colors.white,
              onPressed: () => guardSignedIn(
                () => DonateWidget(
                  community: CommunityProvider.read(context).community,
                  headline: 'Donate to keep the conversation going!',
                  subHeader:
                      'Support ${CommunityProvider.read(context).community.name}!',
                ).show(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShare() {
    final title = Provider.of<CommunityProvider>(context).community.name;
    final subject = 'Join $title on ${Environment.appName}';
    final body = 'Hey, check out $title on ${Environment.appName}!';
    final shareData = AppShareData(subject: subject, body: body);

    return ShareSection(
      iconColor: Theme.of(context).colorScheme.primary,
      iconBackgroundColor: null,
      url: shareData.pathToPage,
      body: body,
      subject: subject,
      wrapIcons: false,
      buttonPadding: 0,
      size: 39,
      iconSize: 16,
      shareCallback: (ShareType type) {
        analytics.logEvent(
          AnalyticsPressShareCommunityLinkEvent(
            // Use a non-listening read: this runs from a tap handler, outside
            // of build, where listening to the provider is not allowed.
            communityId: CommunityProvider.read(context).community.id,
            shareType: type,
          ),
        );
      },
    );
  }

  Widget _buildEvents() {
    return CustomStreamBuilder<List<Event>>(
      entryFrom: '_CommunityHomeState._buildEvents',
      loadingBuilder: (_) => const DelayedLoadingPlaceholder(
        child: PulseLoadingPlaceholder(height: 220),
      ),
      stream: Provider.of<CommunityHomeProvider>(context).eventsStream,
      errorMessage: 'Error loading events. Please refresh!',
      builder: (_, events) {
        if (events == null || events.isEmpty) {
          if (Provider.of<CommunityPermissionsProvider>(context)
              .canEditCommunity) {
            return _buildEmptyEventAdminButton();
          } else if (Provider.of<CommunityPermissionsProvider>(context)
              .canCreateEvent) {
            return EmptyPageContent(
              type: EmptyPageType.events,
              onButtonPress: () => CreateEventDialog.show(context),
            );
          } else {
            return EmptyPageContent(type: EmptyPageType.events);
          }
        } else {
          return Column(
            children: [
              for (var i = 0; i < min(events.length, _eventsToShow); i++) ...[
                EventCard(events[i]),
                SizedBox(height: 20),
              ],
              if (events.length > _eventsToShow)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(
                          () => _eventsToShow += _eventCountIncrement,
                        );
                      },
                      child: Container(
                        width: 150,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(),
                        ),
                        alignment: Alignment.center,
                        child: HeightConstrainedText(
                          'See More Events',
                          style: AppTextStyle.eyebrowSmall,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        }
      },
    );
  }

  Widget _buildEmptyEventAdminButton() => MemoizedStreamBuilder<bool>(
        keys: [community.id],
        streamGetter: () => firestoreEventService.communityHasEvents(
          communityId: community.id,
        ),
        builder: (context, communityHasEvents) {
          return EmptyPageContent(
            type: EmptyPageType.events,
            subtitleText: (communityHasEvents ?? true)
                ? context.l10n.noEventsFound
                : 'Create your first event!',
            onButtonPress: () => CreateEventDialog.show(context),
          );
        },
      );

  Widget _buildContactUsSection(bool showDonations) {
    final email = community.contactEmail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (email != null && email.isNotEmpty) ...[
          SectionHeading('Contact'),
          SizedBox(height: 10),
          GestureDetector(
            onTap: () => url_launcher.launch('mailto:$email'),
            child: Text(
              email,
              // Not colorScheme.secondary: Spaces can theme that to white,
              // which left the address invisible against the page.
              style: AppTextStyle.bodyMedium
                  .copyWith(color: context.theme.colorScheme.onSurface),
            ),
          ),
          SizedBox(height: 20),
        ],
        // These are share targets, not ways to contact the Space -- they were
        // previously unlabelled and read as part of the Contact block.
        SectionHeading('Share'),
        SizedBox(height: 10),
        Row(
          children: [
            _buildShare(),
            Spacer(),
          ],
        ),
        SizedBox(height: 30),
        _buildEngagementButtons(showDonations),
      ],
    );
  }
}
