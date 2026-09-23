import 'package:client/features/auth/utils/auth_utils.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:client/features/community/utils/community_theme_utils.dart.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/discussion_threads/presentation/views/manipulate_discussion_thread_page.dart';
import 'package:client/features/events/features/create_event/presentation/views/create_event_dialog.dart';
import 'package:client/features/templates/presentation/widgets/template_fab.dart';
import 'package:client/features/community/presentation/widgets/community_page_fab.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/features/resources/presentation/views/create_community_resource_modal.dart';
import 'package:client/features/resources/presentation/community_resources_presenter.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/core/widgets/navbar/bottom_nav_bar.dart';
import 'package:client/core/widgets/navbar/custom_scaffold.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/features/user/data/services/user_data_service.dart';
import 'package:client/services.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/utils/meta_tag_service.dart';
import 'package:data_models/community/community.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:client/core/widgets/pulse_loading_placeholder.dart';
import 'package:client/core/widgets/delayed_loading_placeholder.dart';

class CommunityPage extends StatefulWidget {
  final bool fillViewport;
  final bool isCreateEventFabVisible;
  final Widget content;

  const CommunityPage._({
    required this.fillViewport,
    required this.isCreateEventFabVisible,
    required this.content,
  });

  static Widget create({
    required String displayId,
    bool fillViewport = false,
    bool isCreateEventFabVisible = false,
    required Widget content,
  }) {
    return ChangeNotifierProvider(
      create: (context) => CommunityProvider(
        displayId: displayId,
        navBarProvider: Provider.of<NavBarProvider>(context, listen: false),
      )..initialize(),
      child: CommunityPage._(
        fillViewport: fillViewport,
        isCreateEventFabVisible: isCreateEventFabVisible,
        content: content,
      ),
    );
  }

  @override
  CommunityPageState createState() => CommunityPageState();
}

class CommunityPageState extends State<CommunityPage> {
  @override
  void initState() {
    context.read<NavBarProvider>().checkIfShouldResetNav();
    super.initState();
  }

  bool get _showBottomNav {
    final isNavHiddenInNavProvider = context.watch<NavBarProvider>().hideNav;
    final isLocationWithoutNavBar = CheckCurrentLocation.isInstantPage;
    return !isNavHiddenInNavProvider &&
        !isLocationWithoutNavBar &&
        responsiveLayoutService.showBottomNavBar(context);
  }

  @override
  Widget build(BuildContext context) {
    // The Space page paints its own ground in every state, not just the one
    // where it has a Space to show. CustomScaffold -- which is what normally
    // supplies the background -- is built inside the stream's `builder`, so
    // the loading and error states render with nothing behind them at all and
    // fall through to the white page behind the app. Their text still takes
    // the theme's onSurface, which under a dark theme is a pale grey: the
    // error read as unstyled and near-invisible.
    return ColoredBox(
      color: context.theme.colorScheme.surface,
      child: Center(
        child: CustomStreamBuilder<Community?>(
          entryFrom: '_CommunityPageState._buildCommunityContent',
          loadingBuilder: (_) => const DelayedLoadingPlaceholder(
            child: PulseLoadingPlaceholder(height: 320),
          ),
          stream: context.watch<CommunityProvider>().communityStream,
          errorMessage: 'Something went wrong loading this space.',
          builder: (_, community) {
            // BehaviorSubjectWrapper emits active+null before Firestore responds,
            // bypassing CustomStreamBuilder's loading guard. Hold content until
            // community is available so child presenters can safely access communityId.
            if (community == null) return const SizedBox.shrink();

            final currentUrl = html.window.location.href;
            MetaTagService.updateCommunityMetaTags(
              communityName: community.name ?? 'Space',
              communityDescription: community.description,
              communityImageUrl:
                  community.profileImageUrl ?? community.bannerImageUrl,
              communityUrl: currentUrl,
            );

            // Event pages now carry the Space's colours too; admin and template
            // pages stay on the app's default palette.
            final isOnPageWithDefaultColors =
                CheckCurrentLocation.isTemplatePage ||
                    CheckCurrentLocation.isCommunityAdminPage;
            final enableCustomColors = !isOnPageWithDefaultColors;

            // Swaps by brightness, so the admin's validated contrast pair holds
            // in dark mode instead of putting light-on-light.
            final brand = SpaceBrandColors.resolve(
              lightColor: community.themeLightColor,
              darkColor: community.themeDarkColor,
              brightness: Theme.of(context).brightness,
            );
            final brandBackground =
                brand?.background ?? Theme.of(context).colorScheme.surface;
            final brandForeground =
                brand?.foreground ?? context.theme.colorScheme.primary;
            return Consumer<UserService>(
              builder: (_, __, ___) => Consumer<UserDataService>(
                builder: (_, __, ___) {
                  final primaryColor = enableCustomColors
                      ? brandForeground
                      : context.theme.colorScheme.primary;
                  final containerColor = enableCustomColors
                      ? brandBackground
                      : context.theme.colorScheme.primaryContainer;
                  // Overriding a role without its `on` partner breaks the pair
                  // for everything in this subtree: a primary fill kept pulling
                  // the default onPrimary, so on a Space with a dark brand
                  // colour every filled button went dark-on-dark. The two brand
                  // colours are contrast-validated against each other, so each
                  // is the other's readable foreground.
                  final onPrimaryColor = enableCustomColors
                      ? brandBackground
                      : context.theme.colorScheme.onPrimary;
                  final onContainerColor = enableCustomColors
                      ? brandForeground
                      : context.theme.colorScheme.onPrimaryContainer;

                  return ChangeNotifierProvider<CommunityPermissionsProvider>(
                    create: (context) => CommunityPermissionsProvider(
                      communityProvider: Provider.of<CommunityProvider>(
                        context,
                        listen: false,
                      ),
                    )..initialize(),
                    child: Builder(
                      builder: (context) {
                        final isCreateMeetingAvailable =
                            widget.isCreateEventFabVisible &&
                                context
                                    .watch<CommunityPermissionsProvider>()
                                    .canCreateEvent;

                        return CustomScaffold(
                          bgColor: enableCustomColors ? brandBackground : null,
                          fillViewport: widget.fillViewport,
                          bottomNavigationBar: _showBottomNav
                              ? CommunityBottomNavBar(
                                  showCreateMeetingButton:
                                      isCreateMeetingAvailable,
                                )
                              : null,
                          floatingActionButton: _buildFab(context),
                          childTheme: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                                  primary: primaryColor,
                                  onPrimary: onPrimaryColor,
                                  onPrimaryContainer: onContainerColor,
                                  // The Space's light colour is the *background*
                                  // half of a contrast-validated pair (the colour
                                  // picker enforces "light color must be
                                  // lighter"). It used to be assigned to
                                  // `secondary`, which the app reads as a
                                  // foreground -- so every foreground use of
                                  // `secondary` rendered light-on-light and
                                  // vanished on custom-coloured Spaces.
                                  primaryContainer: containerColor,
                                ),
                            switchTheme: SwitchTheme.of(context).copyWith(
                              thumbColor:
                                  WidgetStateColor.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return containerColor;
                                } else {
                                  return primaryColor;
                                }
                              }),
                              trackColor:
                                  WidgetStateColor.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return primaryColor;
                                } else {
                                  return context
                                      .theme.colorScheme.onPrimaryContainer;
                                }
                              }),
                            ),
                            radioTheme: RadioTheme.of(context).copyWith(
                              fillColor: WidgetStateColor.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return primaryColor;
                                } else {
                                  return context
                                      .theme.colorScheme.onPrimaryContainer;
                                }
                              }),
                            ),
                          ),
                          child: widget.content,
                        );
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget? _buildFab(BuildContext context) {
    if (CheckCurrentLocation.isCommunityResourcesPage) {
      final showResourcesFab =
          context.watch<CommunityPermissionsProvider>().canEditCommunity;
      return _buildResourcesFab(isAvailable: showResourcesFab);
    } else if (CheckCurrentLocation.isDiscussionThreadsPage) {
      return _buildDiscussionThreadsFab();
    } else if (CheckCurrentLocation.isTemplatePage) {
      return TemplateFab();
    } else {
      final isCreateMeetingAvailable = widget.isCreateEventFabVisible &&
          context.watch<CommunityPermissionsProvider>().canCreateEvent;

      return _buildCreateMeetingFab(
        isAvailable: !_showBottomNav && isCreateMeetingAvailable,
        context: context,
      );
    }
  }

  Widget? _buildCreateMeetingFab({
    required bool isAvailable,
    required BuildContext context,
  }) =>
      isAvailable
          ? CommunityPageFloatingActionButton(
              text: context.l10n.createAnEvent,
              onTap: () => CreateEventDialog.show(context),
            )
          : null;

  Widget? _buildResourcesFab({required bool isAvailable}) => isAvailable
      ? ChangeNotifierProvider<CommunityResourcesPresenter>(
          create: (_) => CommunityResourcesPresenter(
            communityProvider: context.read<CommunityProvider>(),
          )..initialize(),
          child: Builder(
            builder: (context) {
              return CommunityPageFloatingActionButton(
                onTap: () => CreateCommunityResourceModal.show(context),
                text: context.l10n.addAResource,
              );
            },
          ),
        )
      : null;

  Widget? _buildDiscussionThreadsFab() {
    return CommunityPageFloatingActionButton(
      text: context.l10n.createPost,
      onTap: () => guardSignedIn(
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ManipulateDiscussionThreadPage(
              communityProvider: context.read<CommunityProvider>(),
              discussionThread: null,
            ),
          ),
        ),
      ),
    );
  }
}
