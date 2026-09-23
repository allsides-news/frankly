import 'package:client/core/widgets/constrained_body.dart';
import 'package:flutter/material.dart';
import 'package:client/features/home/presentation/widgets/about_section.dart';
import 'package:client/features/home/presentation/widgets/featured_spaces_section.dart';
import 'package:client/features/home/presentation/widgets/my_communities_section.dart';
import 'package:client/features/home/presentation/widgets/upcoming_events_section.dart';
import 'package:client/features/home/presentation/widgets/sign_in_section.dart';
import 'package:client/core/widgets/navbar/bottom_nav_bar.dart';
import 'package:client/core/widgets/navbar/custom_scaffold.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/services.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/core/utils/meta_tag_service.dart';
import 'package:client/styles/styles.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    context.read<NavBarProvider>().checkIfShouldResetNav();
    // Reset meta tags to default when on home page
    MetaTagService.resetToDefaults();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isUserSignedIn = Provider.of<UserService>(context).isSignedIn;
    return CustomScaffold(
      fillViewport: !isUserSignedIn,
      bottomNavigationBar: responsiveLayoutService.showBottomNavBar(context)
          ? HomeBottomNavBar()
          : null,
      child: isUserSignedIn ? _buildHomePageContent() : HomePageSignInSection(),
    );
  }

  Widget _buildHomePageContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 30),
        if (responsiveLayoutService.isMobile(context))
          ..._buildMobileLayout()
        else
          ..._buildDesktopLayout(),
      ],
    );
  }

  List<Widget> _buildMobileLayout() {
    return [
      RepaintBoundary(
        child: FeaturedSpacesSection(),
      ),
      SizedBox(height: 48),
      RepaintBoundary(
        child: MyCommunitiesSection(),
      ),
      SizedBox(height: 48),
      ConstrainedBody(
        maxWidth: AppSize.kHomeContentMaxWidthMobile,
        child: UpcomingEventsSection.create(),
      ),
      ConstrainedBody(
        maxWidth: AppSize.kHomeContentMaxWidthMobile,
        child: AboutSection(),
      ),
      SizedBox(height: 60),
    ];
  }

  List<Widget> _buildDesktopLayout() {
    return [
      // Featured hugs its cards and the Spaces you follow take the rest of the
      // row. FeaturedSpacesSection carries the gap between them, so a row with
      // nothing featured leaves Following flush to the left margin.
      ConstrainedBody(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            RepaintBoundary(
              child: FeaturedSpacesSection(),
            ),
            Expanded(
              child: RepaintBoundary(
                child: MyCommunitiesSection(),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 48),
      ConstrainedBody(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 1,
              child: UpcomingEventsSection.create(),
            ),
            Expanded(
              flex: 1,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
      ConstrainedBody(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Expanded(
              flex: 1,
              child: AboutSection(),
            ),
            Expanded(
              flex: 1,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ),
      SizedBox(height: 60),
    ];
  }
}
