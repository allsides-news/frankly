import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/constrained_body.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:client/features/community/features/create_community/presentation/views/create_community_dialog.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/events/features/create_event/presentation/views/create_event_dialog.dart';
import 'package:client/features/templates/features/create_template/presentation/views/create_template_dialog.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/features/community/utils/community_theme_utils.dart.dart';
import 'package:client/core/widgets/buttons/app_clickable_widget.dart';
import 'package:client/features/community/presentation/widgets/community_icon_or_logo.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/navbar/community_announcements.dart';
import 'package:client/core/widgets/navbar/nav_bar/nav_bar_contract.dart';
import 'package:client/core/widgets/navbar/nav_bar/nav_bar_model.dart';
import 'package:client/core/widgets/navbar/nav_bar/nav_bar_presenter.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/core/widgets/navbar/profile_or_login.dart';
import 'package:client/core/widgets/navbar/selectable_navigation_icon.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/widgets/step_progress_indicator.dart';
import 'package:client/config/environment.dart';
import 'package:client/app.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/services.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/styles/roundtables_logo.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/community/community.dart';
import 'package:provider/provider.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:client/core/widgets/navbar/nav_bar/space_pill_metrics.dart';

export 'package:client/core/widgets/navbar/nav_bar/space_pill_metrics.dart';

class NavBar extends StatefulWidget {
  NavBar() : super(key: Key('navBar'));

  @override
  NavBarState createState() => NavBarState();
}

class NavBarState extends State<NavBar> implements NavBarView {
  late final NavBarModel _model;
  late final NavBarPresenter _presenter;

  @override
  void initState() {
    super.initState();

    _model = NavBarModel();
    _presenter = NavBarPresenter(context, this, _model);
    _presenter.init();
  }

  void _goToAdminPage() {
    final community = _presenter.getCommunity();
    if (community == null) {
      loggingService.log(
        'NavBarState._goToSettingsPage: Community is null',
        logType: LogType.error,
      );
      return;
    }

    routerDelegate.beamTo(
      CommunityPageRoutes(communityDisplayId: community.displayId)
          .communityAdmin(),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserService>();

    final onboardingStep = _presenter.getCurrentOnboardingStep();
    final isAdminButtonVisible = _presenter.isAdminButtonVisible();
    final isCommunityHomePage = _presenter.isCommunityHomePage();
    final isOnboardingOverviewEnabled =
        _presenter.isOnboardingOverviewEnabled();

    return Column(
      children: [
        if (isOnboardingOverviewEnabled &&
            isCommunityHomePage &&
            isAdminButtonVisible &&
            onboardingStep != null)
          AnimatedSize(
            duration: kTabScrollDuration,
            child: !_model.isOnboardingTooltipShown
                ? SizedBox.shrink()
                : _buildOnboardingOverviewTooltip(onboardingStep),
          ),
        Container(
          color: context.theme.colorScheme.surfaceContainerLowest,
          alignment: Alignment.center,
          child: _buildHeaderContent(),
        ),
        Divider(height: 1, color: AppNeutralColors.of(context).neutral300),
      ],
    );
  }

  @override
  void updateView() {
    setState(() {});
  }

  Widget _buildHeaderContent() {
    final isOnCommunityPage = _presenter.isCommunityLocation();
    final currentCommunity = context.watch<NavBarProvider>().currentCommunity;
    final showBottomNavBar = _presenter.showBottomNavBar(context);
    final isMobile = _presenter.isMobile(context);
    final isInsideSpace = isOnCommunityPage && currentCommunity != null;

    return ConstrainedBody(
      padding: EdgeInsets.only(left: 10, right: 10),
      child: SizedBox(
        height: AppSize.kNavBarHeight,
        child: Row(
          children: [
            // Burger sits at the far left, next to the platform logo, so it
            // reads as platform-level navigation rather than a user menu.
            _buildMenuButton(),
            _buildPlatformLogo(isMobile: isMobile),
            // The Space-specific nav only exists while inside a Space --
            // outside one (e.g. the My Spaces page) this whole pill is absent.
            // Expanded+Align (rather than a Spacer next to a Flexible pill,
            // which would cap the pill at half the free width) right-aligns
            // the pill at its natural size while still handing it a bounded
            // width to ellipsize the Space name against when space is tight.
            if (isInsideSpace)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: kSpacePillMargin,
                    ),
                    child: _buildSpacePill(currentCommunity, isMobile: isMobile),
                  ),
                ),
              )
            else
              Spacer(),
            // On mobile the user avatar lives in the bottom nav bar instead,
            // which is why the mobile nav ends at the Space pill. Event pages
            // are no exception on desktop -- the profile menu stays reachable.
            if (!showBottomNavBar) ProfileOrLogin(showMenuAboveIcon: false),
          ],
        ),
      ),
    );
  }

  /// Opens the platform sidebar. Paired with the logo on the left, per the
  /// same "this is the platform, not you" grouping.
  Widget _buildMenuButton() {
    return Semantics(
      button: true,
      label: context.l10n.showSidebarButton,
      child: IconButton(
        onPressed: () => Scaffold.of(context).openDrawer(),
        icon: Icon(
          Icons.menu,
          size: 34,
          color: context.theme.colorScheme.secondary,
        ),
      ),
    );
  }

  /// The AllSides Roundtables logo -- always the platform mark, never the
  /// current Space's, and always a link back to My Spaces. Mobile drops the
  /// wordmark and keeps just the icon to leave room for the Space pill.
  Widget _buildPlatformLogo({required bool isMobile}) {
    // The mark alone reads smaller than the full lockup at the same height,
    // so mobile keeps 34 while desktop's wordmark sits at 0.75x that.
    const markHeight = 34.0;
    const wordmarkHeight = markHeight * 0.75;

    return Semantics(
      button: true,
      label: context.l10n.franklyLogo,
      child: AppClickableWidget(
        isIcon: false,
        onTap: () => routerDelegate.beamTo(HomeLocation()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: RoundtablesLogo(
            height: isMobile ? markHeight : wordmarkHeight,
            markOnly: isMobile,
          ),
        ),
      ),
    );
  }

  /// The Space-scoped nav: the Space's own avatar and name, its section
  /// links, and its announcements bell, grouped into one bordered stadium so
  /// they read as belonging to the Space rather than to the platform.
  /// How much gap the pill can afford between its icons.
  ///
  /// The icon set is fixed but the width isn't: a Space with Posts enabled on
  /// a 360pt phone has to fit one more icon than a Space without. Spending
  /// whatever is spare, down to a floor, keeps the tap targets as generous as
  /// the screen allows instead of overflowing at one size and looking cramped
  /// at another.
  double _spacePillIconGap(double maxWidth, int iconCount) {
    if (iconCount == 0) return SelectableNavigationIcon.defaultDenseGap;

    final fixed = kSpacePillPadding * 2 +
        kSpacePillBorderWidth * 2 +
        kSpaceLogoSize +
        kSpacePillLogoGap +
        kSpacePillIconSize * iconCount;

    return ((maxWidth - fixed) / iconCount).clamp(
      SelectableNavigationIcon.minDenseGap,
      SelectableNavigationIcon.defaultDenseGap,
    );
  }

  Widget _buildSpacePill(Community community, {required bool isMobile}) {
    final canViewCommunityLinks = _presenter.canViewCommunityLinks();

    // The nav bar is rendered outside CustomScaffold's Space child theme, so
    // it can't pick these up from the ambient ColorScheme -- it resolves them
    // from the Space itself.
    final brand = SpaceBrandColors.resolve(
      lightColor: community.themeLightColor,
      darkColor: community.themeDarkColor,
      brightness: Theme.of(context).brightness,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final iconGap = isMobile
            ? _spacePillIconGap(
                constraints.maxWidth,
                _spaceNavItems(community).length +
                    (canViewCommunityLinks ? 1 : 0),
              )
            : SelectableNavigationIcon.defaultDenseGap;

        return _buildSpacePillBody(
          community,
          isMobile: isMobile,
          brand: brand,
          canViewCommunityLinks: canViewCommunityLinks,
          iconGap: iconGap,
        );
      },
    );
  }

  Widget _buildSpacePillBody(
    Community community, {
    required bool isMobile,
    required SpaceBrandColors? brand,
    required bool canViewCommunityLinks,
    required double iconGap,
  }) {
    final pill = Container(
      // Fixed height so the pill can't be stretched taller by whichever child
      // happens to have the largest minimum size -- that's what was padding
      // the nav out vertically.
      height: kSpacePillHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kSpacePillRadius),
        border: Border.all(
          // A branded pill draws its edge from its own foreground rather than
          // the neutral hairline, which reads as a foreign seam against a
          // colour. Not the brand background: that is what fills the pill, so
          // it made the border invisible -- and a Space whose brand background
          // is near-white then had no edge and no contrast against the nav,
          // leaving nothing to show the pill was there at all.
          //
          // At full strength, not faded. The picker validates the two brand
          // colours against each other at 4.5:1, so the foreground clears
          // WCAG's 3:1 for non-text contrast on any pair a Space can save.
          // Fading it forfeits that guarantee: 25% alpha lands at 1.65:1 on
          // the #EFEFEF/#222222 preset, and no single alpha is safe across
          // the range the picker allows -- the worst case needs 0.78.
          color: brand?.foreground ?? AppNeutralColors.of(context).neutral300,
          width: kSpacePillBorderWidth,
        ),
        color: brand?.background ??
            context.theme.colorScheme.surfaceContainerLowest,
      ),
      // Equal on all four sides, so the gap around the Space logo is the same
      // above/below as it is to the left.
      padding: const EdgeInsets.all(kSpacePillPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMobile)
            _buildSpaceHomeButton(community, isMobile: true)
          else
            // Flexible here (a direct child of this Row) lets the Space name
            // ellipsize when the pill runs out of room, instead of overflowing.
            Flexible(
              child: _buildSpaceHomeButton(community, isMobile: false),
            ),
          // Evens the logo-to-first-icon gap out against the gaps between the
          // icons themselves, which come from their own equal padding.
          if (isMobile) SizedBox(width: kSpacePillLogoGap),
          ..._buildSpaceNavItems(
            community,
            isMobile: isMobile,
            denseGap: iconGap,
          ),
          // Announcements stay gated on the same permission as before, but
          // are now shown on mobile too rather than desktop-only.
          if (canViewCommunityLinks)
            AnnouncementsIcon(
              communityId: community.id,
              // Matches the section icons beside it instead of the larger
              // standalone default.
              iconSize: isMobile ? kSpacePillIconSize : null,
              width: isMobile ? kSpacePillIconSize + iconGap : null,
            ),
        ],
      ),
    );

    if (brand == null) return pill;

    // The pill's contents already read onSurface/onSurfaceVariant, so
    // remapping just those two inside this subtree recolours the name, the
    // section links and the bell against the brand fill without every one of
    // them needing to know about Space colours.
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
              onSurface: brand.foreground,
              onSurfaceVariant: brand.foreground.withValues(alpha: 0.7),
            ),
      ),
      child: pill,
    );
  }

  void _goToSpaceHome(Community community) {
    routerDelegate.beamTo(
      CommunityPageRoutes(communityDisplayId: community.displayId)
          .communityHome,
    );
  }

  /// The Space logo and its name, as a single button back to the Space home.
  /// Mobile has no room for the name, so it's the logo alone.
  Widget _buildSpaceHomeButton(
    Community community, {
    required bool isMobile,
  }) {
    final logo = CommunityCircleIcon(
      community,
      isTooltipShown: false,
      backgroundColor: Colors.transparent,
      imageHeight: kSpaceLogoSize,
      borderRadius: kSpaceLogoRadius,
    );

    return AppClickableWidget(
      isIcon: false,
      // The pill sets its own spacing, and this widget's default 8px inset
      // would both squash the logo out of square and overflow the row.
      padding: EdgeInsets.zero,
      borderRadius: kSpaceLogoRadius,
      tooltipMessage: isMobile ? (community.name ?? '') : null,
      onTap: () => _goToSpaceHome(community),
      child: isMobile
          ? logo
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                logo,
                SizedBox(width: 10),
                Flexible(
                  child: ConstrainedBox(
                    // Caps the name's width; a tighter incoming constraint
                    // wins, and the Text ellipsizes rather than overflowing.
                    constraints: BoxConstraints(maxWidth: 220),
                    child: Text(
                      community.name ?? Environment.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Using GoogleFonts.geist directly (not .copyWith on the
                      // theme style) so the Semibold font file actually gets
                      // loaded -- google_fonts only lazy-loads weights
                      // requested this way.
                      style: GoogleFonts.geist(
                        textStyle: context.theme.textTheme.titleMedium,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
              ],
            ),
    );
  }

  /// The enabled sections, as data. Split out from [_buildSpaceNavItems] so
  /// the pill can count them before it lays anything out -- how much gap it
  /// can afford depends on how many icons it has to fit.
  List<_SpaceNavItem> _spaceNavItems(Community community) {
    final communityDisplayId = community.displayId;
    final enableDiscussionThreads = kShowDiscussionThreadsNav &&
        community.settingsMigration.enableDiscussionThreads;
    final showResources = Provider.of<NavBarProvider>(context).showResources;

    final items = <_SpaceNavItem>[
      _SpaceNavItem(
        title: context.l10n.events,
        icon: Icons.calendar_month_outlined,
        isSelected: CheckCurrentLocation.isCommunitySchedulePage,
        onTap: () => routerDelegate.beamTo(
          CommunityPageRoutes(communityDisplayId: communityDisplayId)
              .eventsPage,
        ),
      ),
      if (enableDiscussionThreads)
        _SpaceNavItem(
          title: context.l10n.posts,
          icon: Icons.forum_outlined,
          isSelected: CheckCurrentLocation.isDiscussionThreadsPage,
          onTap: () => routerDelegate.beamTo(
            CommunityPageRoutes(communityDisplayId: communityDisplayId)
                .discussionThreadsPage,
          ),
        ),
      if (showResources)
        _SpaceNavItem(
          title: context.l10n.resources,
          // Resources are always links -- community_resources.dart taps
          // straight through to resource.url.
          icon: Icons.link_outlined,
          isSelected: CheckCurrentLocation.isCommunityResourcesPage,
          onTap: () => routerDelegate.beamTo(
            CommunityPageRoutes(communityDisplayId: communityDisplayId)
                .resourcesPage,
          ),
        ),
      _SpaceNavItem(
        title: context.l10n.templates,
        // Stacked documents. A bordered list was too close to the dots in
        // the calendar icon beside it. (The mortarboard this replaces is
        // still used by the prerequisite-template badge, where it means
        // something else.)
        icon: Icons.file_copy_outlined,
        isSelected: CheckCurrentLocation.isCommunityTemplatesPage,
        onTap: () => routerDelegate.beamTo(
          CommunityPageRoutes(communityDisplayId: communityDisplayId)
              .browseTemplatesPage,
        ),
      ),
    ];

    return items;
  }

  /// One entry per enabled section, as text on desktop and as an icon on
  /// mobile. Both platforms show the same set, so a Space's sections don't
  /// silently disappear on a phone.
  List<Widget> _buildSpaceNavItems(
    Community community, {
    required bool isMobile,
    required double denseGap,
  }) {
    return [
      for (final item in _spaceNavItems(community))
        if (isMobile)
          // Dense: the default 48px tap box per icon overflowed the pill on
          // narrow screens once Templates joined the set.
          SelectableNavigationIcon(
            iconData: item.icon,
            label: item.title,
            isSelected: item.isSelected,
            iconSize: kSpacePillIconSize,
            dense: true,
            denseGap: denseGap,
            onTap: item.onTap,
          )
        else
          _SelectableNavigationButton(
            title: item.title,
            onTap: item.onTap,
            isSelected: item.isSelected,
          ),
    ];
  }

  /// Foreground here is onPrimaryContainer, not onPrimary: this bar is painted
  /// with primaryContainer, and in the dark scheme onPrimary and
  /// primaryContainer are both neutral800 -- identical, so the text vanished.
  Widget _buildOnboardingOverviewTooltip(OnboardingStep onboardingStep) {
    _presenter.updateAdminButtonXPosition();

    final onboardingSteps = List.from(OnboardingStep.values);
    if (!kShowStripeFeatures) {
      onboardingSteps.remove(OnboardingStep.createStripeAccount);
    }

    final totalSteps = onboardingSteps.length;
    final completedStepCount = _presenter.getCompletedStepCount();
    final totalWidth = MediaQuery.of(context).size.width;
    final settingsXPosition = _model.adminButtonXPosition;
    final isMobile = _presenter.isMobile(context);

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: BoxDecoration(
              color: context.theme.colorScheme.primaryContainer,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: StepProgressIndicator(
                        completedStepCount: completedStepCount,
                        totalSteps: totalSteps,
                        backgroundColor: context.theme.colorScheme.onPrimaryContainer,
                        progressColor:
                            context.theme.colorScheme.primaryFixedDim,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '$completedStepCount/$totalSteps',
                      style: AppTextStyle.body
                          .copyWith(color: context.theme.colorScheme.onPrimaryContainer),
                    ),
                    SizedBox(width: 20),
                    AppClickableWidget(
                      child: ProxiedImage(
                        null,
                        asset: AppAsset.kXWhitePng,
                        width: 20,
                        height: 20,
                      ),
                      onTap: () => _presenter.closeOnboardingTooltip(),
                    ),
                  ],
                ),
                AppClickableWidget(
                  isIcon: false,
                  onTap: () => _getOnTap(onboardingStep),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ProxiedImage(
                            null,
                            asset: onboardingStep.titleIconPath,
                            width: 16,
                            height: 16,
                          ),
                          SizedBox(width: 5),
                          Text(
                            onboardingStep.title,
                            style: AppTextStyle.bodyMedium.copyWith(
                              color: context.theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            onboardingStep.sectionTitle,
                            style: AppTextStyle.bodyMedium.copyWith(
                              color: context.theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: context.theme.colorScheme.onPrimaryContainer,
                            size: 12,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (settingsXPosition != null)
            SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Positioned(
                    // Finds the center of the relevant widget.
                    right: totalWidth - settingsXPosition - 25,
                    child: CustomPaint(
                      size: Size(20, 10),
                      painter: TrianglePainter(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    } else {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: BoxDecoration(
              color: context.theme.colorScheme.primaryContainer,
            ),
            child: ConstrainedBody(
              maxWidth: 1100,
              child: Row(
                children: [
                  AppClickableWidget(
                    isIcon: false,
                    onTap: () => _getOnTap(onboardingStep),
                    child: Row(
                      children: [
                        ProxiedImage(
                          null,
                          asset: onboardingStep.titleIconPath,
                          width: 16,
                          height: 16,
                        ),
                        SizedBox(width: 5),
                        Text(
                          onboardingStep.title,
                          style: AppTextStyle.bodyMedium.copyWith(
                            color: context.theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          onboardingStep.sectionTitle,
                          style: AppTextStyle.bodyMedium.copyWith(
                            color: context.theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: context.theme.colorScheme.onPrimaryContainer,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                  Spacer(),
                  SizedBox(
                    width: 300,
                    child: StepProgressIndicator(
                      completedStepCount: completedStepCount,
                      totalSteps: totalSteps,
                      backgroundColor: context.theme.colorScheme.onPrimaryContainer,
                      progressColor: context.theme.colorScheme.primaryFixedDim,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '$completedStepCount/$totalSteps',
                    style: AppTextStyle.body
                        .copyWith(color: context.theme.colorScheme.onPrimaryContainer),
                  ),
                  SizedBox(width: 20),
                  AppClickableWidget(
                    child: ProxiedImage(
                      null,
                      asset: AppAsset.kXWhitePng,
                      width: 20,
                      height: 20,
                    ),
                    onTap: () => _presenter.closeOnboardingTooltip(),
                  ),
                ],
              ),
            ),
          ),
          if (settingsXPosition != null)
            Container(
              // Making optical illusion that `triangle` is overlapping app bar.
              color: context.theme.colorScheme.surfaceContainerLowest,
              height: 10,
              child: Stack(
                children: [
                  Positioned(
                    // Finds the center of the relevant widget.
                    right: totalWidth - settingsXPosition - 25,
                    child: CustomPaint(
                      size: Size(20, 10),
                      painter: TrianglePainter(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
  }

  Future<void> _getOnTap(OnboardingStep onboardingStep) async {
    switch (onboardingStep) {
      case OnboardingStep.brandSpace:
        final community = _presenter.getCommunity();

        await CreateCommunityDialog(community: community).show();
        break;
      case OnboardingStep.createGuide:
        await CreateTemplateDialog.show(
          communityProvider: context.read<CommunityProvider>(),
          communityPermissionsProvider:
              context.read<CommunityPermissionsProvider>(),
        );
        break;
      case OnboardingStep.hostEvent:
        await CreateEventDialog.show(context);
        break;
      case OnboardingStep.inviteSomeone:
        _goToAdminPage();
        break;
      case OnboardingStep.createStripeAccount:
        await alertOnError(
          context,
          () => _presenter.proceedToConnectWithStripePage(),
        );
        break;
    }
  }
}

/// One section of the Space pill, rendered as text on desktop and as an icon
/// on mobile.
class _SpaceNavItem {
  final String title;

  /// One outlined glyph per section, in a single family.
  ///
  /// No filled-when-selected variant: Material's "Rounded" family is a corner
  /// treatment rather than a fill, so stroke-built shapes like `link` look
  /// virtually identical either way. Selection is already carried by the
  /// icon's colour and the indicator bar under it.
  final IconData icon;

  final bool isSelected;
  final void Function() onTap;

  const _SpaceNavItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });
}

class _SelectableNavigationButton extends StatelessWidget {
  final void Function() onTap;
  final bool isSelected;
  final String title;

  const _SelectableNavigationButton({
    Key? key,
    required this.title,
    required this.onTap,
    required this.isSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ActionButton(
      type: ActionButtonType.text,
      onPressed: onTap,
      // Without these the button's default 96x50 minimum size would set the
      // pill's height and spread the links far apart.
      height: kSpaceLogoSize,
      minWidth: 0,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: context.theme.colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              )
            : null,
        child: HeightConstrainedText(
          // Uppercased for the nav treatment rather than in the l10n string,
          // so the same string stays sentence-case everywhere else it's used.
          title.toUpperCase(),
          style: context.theme.textTheme.labelLarge!.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w500,
            color: isSelected
                ? context.theme.colorScheme.onSurface
                : context.theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Draws downwards pointing triangle.
class TrianglePainter extends CustomPainter {
  final Paint painter;

  TrianglePainter(BuildContext context)
      : painter = Paint()
          ..color = context.theme.colorScheme.primary
          ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.lineTo(size.width, 0.0);
    path.lineTo(size.width / 2, size.height);
    path.close();

    canvas.drawPath(path, painter);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
