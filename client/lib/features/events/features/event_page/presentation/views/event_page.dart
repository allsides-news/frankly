import 'dart:async';

import 'package:client/core/utils/toast_utils.dart';
import 'package:client/core/widgets/confirm_dialog.dart';
import 'package:client/core/widgets/constrained_body.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/events/features/event_page/presentation/views/event_page_contract.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_page_meeting_agenda.dart';
import 'package:client/features/events/features/event_page/data/providers/event_page_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_tabs.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/presentation/views/meeting_dialog.dart';
import 'package:client/features/events/features/event_page/data/providers/template_provider.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_info.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/features/auth/presentation/views/sign_in_dialog.dart';
import 'package:client/core/widgets/tabs/tab_bar.dart';
import 'package:client/core/widgets/tabs/tab_bar_view.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/utils/dialogs.dart';
import 'package:client/core/utils/meta_tag_service.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/event_message.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../event_page_presenter.dart';
import 'package:client/core/widgets/pulse_loading_placeholder.dart';
import 'package:client/core/widgets/delayed_loading_placeholder.dart';

class EventPage extends StatefulWidget {
  final String templateId;
  final String eventId;
  final bool cancel;
  final String? uid;

  const EventPage({
    required this.templateId,
    required this.eventId,
    required this.cancel,
    this.uid,
    Key? key,
  }) : super(key: key);

  Widget create() {
    return ChangeNotifierProvider(
      create: (context) => EventProvider(
        communityProvider: context.read<CommunityProvider>(),
        templateId: templateId,
        eventId: eventId,
      )..initialize(),
      child: ChangeNotifierProvider(
        create: (context) => TemplateProvider(
          communityId: context.read<CommunityProvider>().communityId,
          templateId: templateId,
        )..initialize(),
        child: ChangeNotifierProvider(
          create: (context) => EventPageProvider(
            eventProvider: context.read<EventProvider>(),
            communityProvider: context.read<CommunityProvider>(),
            navBarProvider: context.read<NavBarProvider>(),
            cancelParam: cancel,
          ),
          child: ChangeNotifierProvider(
            create: (context) => EventPermissionsProvider(
              eventProvider: context.read<EventProvider>(),
              communityPermissions:
                  context.read<CommunityPermissionsProvider>(),
              communityProvider: context.read<CommunityProvider>(),
            )..initialize(),
            child: this,
          ),
        ),
      ),
    );
  }

  @override
  EventPageState createState() => EventPageState();
}

class EventPageState extends State<EventPage> implements EventPageView {
  EventProvider get _eventProvider => EventProvider.watch(context);

  Event get event => _eventProvider.event;

  bool get userIsJoined => _eventProvider.isParticipant;

  EventSettings get eventSettings {
    final eventSettings =
        context.watch<EventProvider>().eventOrNull?.eventSettings;
    final communityEventSettings =
        context.watch<CommunityProvider>().eventSettings;

    return eventSettings ?? communityEventSettings;
  }

  Widget _buildEventLoading() => const DelayedLoadingPlaceholder(
        child: PulseLoadingPlaceholder(height: 320),
      );

  late final EventPagePresenter _presenter;

  // This is to rebuild the page when the in-meeting query parameter is applied
  void onRouterUpdate() => setState(() {});

  @override
  void initState() {
    EventProvider.read(context).initialize();
    context.read<TemplateProvider>().initialize();
    context.read<EventPageProvider>().initialize();

    if (!userService.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!userService.isSignedIn) {
          SignInDialog.show();
        }
      });
    }

    routerDelegate.addListener(onRouterUpdate);

    super.initState();

    _presenter = EventPagePresenter(context, this);
    _presenter.init();
  }

  @override
  void dispose() {
    routerDelegate.removeListener(onRouterUpdate);
    super.dispose();
  }

  @override
  void updateView() {
    if (mounted) setState(() {});
  }

  Future<JoinEventResults> _joinEvent({
    bool showConfirm = true,
    bool joinCommunity = false,
    bool optInToNewsletters = false,
    bool showBreakoutSurveyDialog = true,
    bool showPreEventCta = true,
  }) async {
    return await alertOnError<JoinEventResults>(
          context,
          () => context.read<EventPageProvider>().joinEvent(
                showConfirm: showConfirm,
                joinCommunity: joinCommunity,
                optInToNewsletters: optInToNewsletters,
                showBreakoutSurveyDialog: showBreakoutSurveyDialog,
                showPreEventCta: showPreEventCta,
              ),
        ) ??
        JoinEventResults(isJoined: false);
  }

  Future<void> _startMeeting() async {
    final eventPageProvider = context.read<EventPageProvider>();
    final eventProvider = EventProvider.read(context);
    JoinEventResults? joinResults;
    if (!eventProvider.isParticipant) {
      // Skip the CTA and smart-match dialogs here; enterMeeting shows both
      // so the order is CTA -> smart match -> enter.
      joinResults = await _joinEvent(
        showConfirm: false,
        showBreakoutSurveyDialog: false,
        showPreEventCta: false,
      );
      // Re-check the actual participant state in case the join succeeded but
      // a later step (e.g. the CTA dialog) reported a failure.
      if (!joinResults.isJoined && !eventProvider.isParticipant) {
        return;
      }
    }
    if (!mounted) return;
    await alertOnError(
      context,
      () => eventPageProvider.enterMeeting(
        surveyQuestions: joinResults?.surveyQuestions,
      ),
    );
  }

  Future<void> _showSendMessageDialog() async {
    final isMobile = responsiveLayoutService.isMobile(context);

    final message = await Dialogs.showComposeMessageDialog(
      context,
      title: context.l10n.messageParticipants,
      isMobile: isMobile,
      labelText: 'Message',
      validator: (message) =>
          message == null || message.isEmpty ? 'Message cannot be empty' : null,
      positiveButtonText: 'Send',
    );

    if (!mounted) return;
    if (message != null) {
      await alertOnError(context, () => _presenter.sendMessage(message));
    }
  }

  Future<void> _showRemoveMessageDialog(
    EventMessage eventMessage,
  ) async {
    await showCustomDialog(
      builder: (context) {
        return ConfirmDialog(
          title: 'Are you sure you want to remove this message?',
          cancelText: context.l10n.cancel,
          onCancel: (context) {
            Navigator.pop(context);
          },
          onConfirm: (context) => alertOnError(context, () async {
            await _presenter.removeMessage(eventMessage);
            if (!context.mounted) return;
            Navigator.pop(context);
          }),
        );
      },
    );
  }

  bool _isEnterEventGraphicShown(Event event, DateTime scheduled) {
    final isParticipant = EventProvider.watch(context).isParticipant;
    final now = clockService.now();
    final beforeMeetingCutoff = scheduled.subtract(Duration(minutes: 10));
    final afterMeetingCutoff = scheduled.add(Duration(hours: 2));
    final hasEnded = event.hasEnded(now);

    return isParticipant &&
        !hasEnded &&
        now.isAfter(beforeMeetingCutoff) &&
        now.isBefore(afterMeetingCutoff);
  }

  Widget _buildGuide() {
    final event = _eventProvider.eventOrNull;
    if (event == null) return _buildEventLoading();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (event.scheduledTime != null &&
            _isEnterEventGraphicShown(event, event.scheduledTime!)) ...[
          CustomInkWell(
            onTap: _startMeeting,
            child: SizedBox(
              height: 380,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ProxiedImage(
                      null,
                      asset: AppAsset('media/background.gif'),
                      fit: BoxFit.cover,
                      loadingColor: Colors.transparent,
                    ),
                  ),
                  Container(
                    color: context.theme.colorScheme.scrim.withScrimOpacity,
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HeightConstrainedText(
                          'The event is starting',
                          style: TextStyle(
                            color: context.theme.colorScheme.onPrimary,
                          ),
                        ),
                        SizedBox(height: 10),
                        ActionButton(
                          text: 'Enter Event',
                          onPressed: _startMeeting,
                          height: 65,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 4),
        ],
        CustomTabBar(
          padding: EdgeInsets.zero,
        ),
        SizedBox(height: 16),
        CustomTabBarView(keepAlive: !responsiveLayoutService.isMobile(context)),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildEventTabsWrappedGuide() {
    final eventProvider = EventProvider.watch(context);
    final isInBreakouts =
        LiveMeetingProvider.watchOrNull(context)?.isInBreakout ?? false;
    final isParticipant = eventProvider.isParticipant;
    final isMod =
        Provider.of<CommunityPermissionsProvider>(context).canModerateContent;
    final canEdit =
        Provider.of<CommunityPermissionsProvider>(context).canEditCommunity;

    final hasPrePostContent =
        (eventProvider.eventOrNull?.preEventCardData?.hasData ?? false) ||
            (eventProvider.eventOrNull?.postEventCardData?.hasData ?? false);

    final bool enableGuide = isInBreakouts ||
        eventProvider.agendaPreview ||
        context.watch<EventPermissionsProvider>().isAgendaVisibleOverride;

    final eventPermissions = context.watch<EventPermissionsProvider>();

    return EventTabsWrapper(
      onRemoveMessage: (eventMessage) => _showRemoveMessageDialog(eventMessage),
      meetingAgendaBuilder: (context) => EventPageMeetingAgenda(),
      enableChat: (eventPermissions.canChat && eventProvider.enableChat),
      enablePrePostEvent: canEdit || (isParticipant && hasPrePostContent),
      enableMessages: isParticipant || isMod,
      enableGuide: enableGuide,
      child: _buildGuide(),
    );
  }

  Widget _buildMainContent() {
    final isMobile = responsiveLayoutService.isMobile(context);
    final eventProvider = EventProvider.watch(context);
    final event = eventProvider.eventOrNull;
    if (event == null) return _buildEventLoading();

    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          if (_presenter.isEditTemplateTooltipShown)
            _buildEditTemplateMessage(),
          if (isMobile) ...[
            Container(
              alignment: Alignment.topCenter,
              child: EventInfo(
                eventPagePresenter: _presenter,
                event: event,
                onMessagePressed: () => _showSendMessageDialog(),
                onJoinEvent: _joinEvent,
              ),
            ),
            SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildEventTabsWrappedGuide(),
            ),
          ] else ...[
            SizedBox(height: 40),
            ConstrainedBody(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 400,
                    alignment: Alignment.topCenter,
                    child: EventInfo(
                      eventPagePresenter: _presenter,
                      event: event,
                      onMessagePressed: () => _showSendMessageDialog(),
                      onJoinEvent: _joinEvent,
                    ),
                  ),
                  SizedBox(width: 40),
                  Expanded(
                    child: _buildEventTabsWrappedGuide(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditTemplateMessage() {
    final templateId = _eventProvider.eventOrNull?.templateId;
    if (templateId == null) return const SizedBox.shrink();
    return Container(
      color: context.theme.colorScheme.surfaceContainerHigh,
      padding: EdgeInsets.symmetric(vertical: 20),
      child: ConstrainedBody(
        maxWidth: 1100,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  text: 'You are editing an individual event. \n',
                  style: context.theme.textTheme.titleMedium!.copyWith(
                    color: context.theme.colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                  children: [
                    TextSpan(
                      text: 'If you want to edit future instances, ',
                      style: context.theme.textTheme.bodyMedium!.copyWith(
                        color: context.theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: context.l10n.editTheCommunityTemplate,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => routerDelegate.beamTo(
                              CommunityPageRoutes(
                                communityDisplayId:
                                    Provider.of<CommunityProvider>(
                                  context,
                                  listen: false,
                                ).displayId,
                              ).templatePage(templateId: templateId),
                            ),
                      style: context.theme.textTheme.bodyMedium!.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: () => _presenter.hideEditTooltip(),
              icon: Icon(
                Icons.close,
                color: context.theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInToViewEvent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeightConstrainedText(
                context.l10n.signUpOrSignInToContinue,
                textAlign: TextAlign.center,
                style: context.theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ActionButton(
                text: context.l10n.signIn,
                expand: true,
                onPressed: () => SignInDialog.show(newUser: false),
              ),
              const SizedBox(height: 8),
              ActionButton(
                type: ActionButtonType.outline,
                text: context.l10n.signUp,
                expand: true,
                onPressed: () => SignInDialog.show(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventProvider = context.watch<EventProvider>();
    final isSignedIn = context.watch<UserService>().isSignedIn;

    if (context.watch<EventPageProvider>().isEnteredMeeting) {
      final isInstant = context.watch<EventPageProvider>().isInstant;
      // Ensure event is loaded in event stream before it is accessed
      return CustomStreamBuilder<Event>(
        showLoading: false,
        entryFrom: '_EventPageState.buildMeetingDialog',
        stream: Provider.of<EventProvider>(context).eventStream,
        builder: (context, snapshot) {
          if (snapshot == null || eventProvider.eventOrNull == null) {
            return const SizedBox.shrink();
          }
          final eventPermissions = context.read<EventPermissionsProvider>();
          return MeetingDialog.create(
            avCheckEnabled: eventPermissions.avCheckEnabled,
            isInstant: isInstant,
            onLeave: context.read<EventPageProvider>().leaveMeetingPrescreen,
          );
        },
      );
    }

    return CustomStreamBuilder<Event>(
      entryFrom: '_EventPageState.build',
      loadingBuilder: (_) => _buildEventLoading(),
      stream: eventProvider.eventStream,
      errorBuilder: (_) => isSignedIn
          ? SizedBox(
              height: 200,
              child: Center(
                child: HeightConstrainedText(
                  context.l10n.somethingWentWrong,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : _buildSignInToViewEvent(),
      builder: (_, event) => CustomStreamBuilder<List<Participant>>(
        entryFrom: '_EventPageState.build',
        loadingBuilder: (_) => _buildEventLoading(),
        stream: eventProvider.eventParticipantsStream,
        // Roster reads can fail (private event before RSVP) without
        // blocking the event landing page itself.
        errorBuilder: (_) {
          if (event == null || eventProvider.eventOrNull == null) {
            return _buildEventLoading();
          }
          return _buildMainContent();
        },
        builder: (_, __) {
          if (event == null || eventProvider.eventOrNull == null) {
            return _buildEventLoading();
          }

          // Update meta tags for social sharing when event loads
          final community = context.watch<CommunityProvider>().community;
          final currentUrl = html.window.location.href;
          final communityName = community.name ?? 'Space';
          MetaTagService.updateEventMetaTags(
            eventTitle: event.title ?? 'Event',
            eventDescription: event.description,
            eventImageUrl: event.image,
            eventUrl: currentUrl,
            communityName: communityName,
          );

          return _buildMainContent();
        },
      ),
    );
  }

  @override
  void showMessage(String message, {ToastType toastType = ToastType.neutral}) {
    showRegularToast(context, message, toastType: toastType);
  }
}

class ExpandedOnDesktop extends StatelessWidget {
  const ExpandedOnDesktop({
    Key? key,
    this.flex = 1,
    required this.child,
  }) : super(key: key);

  final Widget child;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return responsiveLayoutService.isMobile(context)
        ? child
        : Expanded(flex: flex, child: child);
  }
}
