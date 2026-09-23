import 'dart:math';

import 'package:client/core/utils/date_utils.dart';
import 'package:client/core/utils/navigation_utils.dart';
import 'package:client/core/utils/toast_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/events/features/create_event/presentation/views/create_event_dialog.dart';
import 'package:client/features/events/features/event_page/presentation/event_page_presenter.dart';
import 'package:client/features/events/features/event_page/data/providers/event_page_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/presentation/views/event_settings_drawer.dart';
import 'package:client/features/events/features/edit_event/presentation/views/edit_event_drawer.dart';
import 'package:client/features/events/features/event_page/data/providers/template_provider.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/calendar_menu_button.dart';
import 'package:client/core/widgets/buttons/circle_icon_button.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_pop_up_menu_button.dart';
import 'package:client/features/events/features/event_page/presentation/views/participants_dialog.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/warning_info.dart';
import 'package:client/features/community/presentation/widgets/carousel/time_indicator.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/features/templates/features/create_template/presentation/views/create_custom_template_page.dart';
import 'package:client/features/templates/features/create_template/presentation/views/create_template_dialog.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/features/community/presentation/widgets/share_section.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/confirm_dialog.dart';
import 'package:client/features/events/presentation/widgets/event_participants_list.dart';
import 'package:client/features/events/presentation/widgets/hostless_mark.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/features/community/presentation/widgets/community_tag_builder.dart';
import 'package:client/features/templates/presentation/widgets/prerequisite_template_widget.dart';
import 'package:client/config/environment.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/features/user/data/services/user_data_service.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/utils/dialogs.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/features/events/presentation/widgets/periodic_builder.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/utils/share_type.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/templates/template.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:client/features/events/data/event_template_ids.dart';

enum _ParticipantStatus {
  needsParticipants,
  full,
}

class EventInfo extends StatefulHookWidget {
  static const Key enterEventButtonKey = Key('enter-button');
  static const Key rsvpButtonKey = Key('rsvp-button');

  final Event event;
  final void Function() onMessagePressed;
  final EventPagePresenter eventPagePresenter;
  final Future<JoinEventResults> Function({
    bool showConfirm,
    bool joinCommunity,
    bool optInToNewsletters,
    bool showBreakoutSurveyDialog,
    bool showPreEventCta,
  }) onJoinEvent;

  const EventInfo({
    Key? key,
    required this.event,
    required this.onMessagePressed,
    required this.onJoinEvent,
    required this.eventPagePresenter,
  }) : super(key: key);

  @override
  _EventInfoState createState() => _EventInfoState();
}

class _EventInfoState extends State<EventInfo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      analytics.logPageView(
        'event_page',
        communityId: widget.event.communityId,
        eventId: widget.event.id,
      );
    });
  }

  EventProvider get _eventProvider => Provider.of<EventProvider>(context);

  BehaviorSubjectWrapper<List<Featured>>? _featuredStream;

  /// Holds state for a checkbox indicating if the user should automatically join the community when
  /// RSVPing
  bool _joinCommunityDuringRsvp = true;

  /// Holds state for a checkbox indicating if the user opted in to newsletters
  bool _optInToNewsletters = true;

  /// The American Dream jump-page flow should keep the registration card focused
  /// on the primary register action by hiding follow/newsletter opt-in CTAs.
  bool get _showRsvpOptInCtas =>
      _event.templateId != nationalRoundtableOnTheAmericanDreamTemplateId;

  Event get _event => _eventProvider.event;

  bool get _isParticipant => _eventProvider.isParticipant;

  bool get _canModerateEvent =>
      Provider.of<CommunityPermissionsProvider>(context).canModerateContent;

  bool get _canEditCommunity =>
      Provider.of<CommunityPermissionsProvider>(context).canEditCommunity;

  bool get _canEditEvent =>
      Provider.of<EventPermissionsProvider>(context).canEditEvent;

  Membership get _membership => Provider.of<UserDataService>(context)
      .getMembership(Provider.of<CommunityProvider>(context).communityId);

  bool get hasPrerequisiteTemplate =>
      widget.event.prerequisiteTemplateId != null;

  EventPagePresenter get _presenter => widget.eventPagePresenter;

  bool get showPrerequisiteWarning =>
      hasPrerequisiteTemplate &&
      !_eventProvider.hasAttendedPrerequisite &&
      !_isParticipant &&
      !_canEditCommunity;

  bool _canShowFollowCommunity() {
    final isMember = _membership.isMember;
    final doesContainRequireApprovalToJoinFlag =
        _eventProvider.communityProvider.settings.requireApprovalToJoin;

    return !isMember && !doesContainRequireApprovalToJoinFlag;
  }

  @override
  void dispose() {
    super.dispose();
    _featuredStream?.dispose();
  }

  _ParticipantStatus get _status {
    if (!_eventProvider.event.isHosted) {
      return _ParticipantStatus.needsParticipants;
    }

    final maxParticipants = _event.maxParticipants ?? 0;

    if (_eventProvider.participantCount >= maxParticipants) {
      return _ParticipantStatus.full;
    } else {
      return _ParticipantStatus.needsParticipants;
    }
  }

  Future<void> _cancelEvent() {
    return alertOnError(
      context,
      () => context.read<EventPageProvider>().cancelEvent(),
    );
  }

  Future<void> _cancelParticipation() {
    return alertOnError(
      context,
      () => context
          .read<EventProvider>()
          .cancelParticipation(participantId: userService.currentUserId!),
    );
  }

  /// generates and downloads ics content as file on browsers
  /// see https://github.com/AnandChowdhary/calendar-link/issues/208#issuecomment-691675931
  void _downloadICSfile(String icsDataString) {
    /// write ics content into a Blob,
    final blob = html.Blob([icsDataString], 'text/plain', 'native');
    html.AnchorElement(
      href: html.Url.createObjectUrlFromBlob(blob).toString(),
    )
      ..setAttribute('download', 'invite.ics')
      ..click();
  }

  String _getShareBody() {
    var body = 'Join an event with me on ${Environment.appName}!';
    final Community community =
        Provider.of<CommunityProvider>(context).community;
    if (_event.title != null && community.name != null) {
      body =
          'Join me in a conversation about "${_event.title}" on ${community.name}!';
    }
    return body;
  }

  String _getShareUrl() {
    final url = routerDelegate.currentConfiguration?.uri.toString();
    final shareLink = '${Environment.shareLinkUrl}$url';
    return shareLink;
  }

  Future<void> _showCreateGuideFromEventDialog(
    CommunityProvider communityProvider,
  ) async {
    final template = _presenter.getCombinedTemplateFromEvent();
    if (template == null) {
      showRegularToast(
        context,
        'Template is still loading. Please try again in a moment.',
        toastType: ToastType.neutral,
      );
      return;
    }
    final newId = firestoreDatabase.generateNewDocId(
      collectionPath: firestoreDatabase
          .templatesCollection(communityProvider.community.id)
          .path,
    );
    await CreateTemplateDialog.show(
      communityPermissionsProvider:
          Provider.of<CommunityPermissionsProvider>(context, listen: false),
      communityProvider: communityProvider,
      template: template.copyWith(id: newId),
      templateActionType: TemplateActionType.duplicate,
    );
  }

  Future<void> _showDuplicateEventDialog() async {
    final template = context.read<TemplateProvider>().templateOrNull;
    final event = EventProvider.read(context).eventOrNull;
    if (template == null || event == null) {
      showRegularToast(
        context,
        'Event details are still loading. Please try again in a moment.',
        toastType: ToastType.neutral,
      );
      return;
    }
    await CreateEventDialog.show(
      context,
      template: template,
      eventType: event.eventType,
      eventTemplate: event,
    );
  }

  Future<void> _showRefreshGuideDialog() async {
    await ConfirmDialog(
      title: context.l10n.confirmRefreshGuide,
      subText: 'Your event will be reset to the original template. '
          'The list of attendees will not be affected.',
      confirmText: 'Yes, refresh',
      onConfirm: (context) async {
        await alertOnError(context, () async {
          await _presenter.refreshEvent();
          Navigator.pop(context);
        });
      },
      cancelText: context.l10n.cancel,
    ).show();
  }

  Future<void> _downloadRegistrationData() async {
    final eventProvider = EventProvider.read(context);
    await alertOnError(context, () async {
      // Open new stream to ensure we always get data (even in the case of 'livestream' event type)
      final participantsWrapper = firestoreEventService.eventParticipantsStream(
        communityId: widget.event.communityId,
        templateId: widget.event.templateId,
        eventId: widget.event.id,
      );
      final participants = await participantsWrapper.stream
          .map((s) => s.where((p) => p.status == ParticipantStatus.active))
          .first;
      final List<String> userIds = participants.map((p) => p.id).toList();
      await participantsWrapper.dispose();

      final members = await _presenter.getMembersData(userIds);
      if (members.isNotEmpty) {
        await eventProvider.generateRegistrationDataCsvFile(
          registrationData: members,
          eventId: eventProvider.eventId,
        );
      } else {
        showRegularToast(
          context,
          'No members data',
          toastType: ToastType.neutral,
        );
      }
    });
  }

  Future<void> _downloadChatsAndSuggestions() async {
    final eventProvider = EventProvider.read(context);
    await alertOnError(context, () async {
      final response = await _presenter.getChatsAndSuggestions();
      final chatsSuggesions = response.chatsSuggestionsList ?? [];
      if (chatsSuggesions.isNotEmpty) {
        await eventProvider.generateChatAndSugguestionsDataCsv(
          response: response,
          eventId: eventProvider.eventId,
        );
      } else {
        showRegularToast(
          context,
          'No chats or suggestions data',
          toastType: ToastType.neutral,
        );
      }
    });
  }

  Widget _buildOptionsIcon() {
    final isMobile = responsiveLayoutService.isMobile(context);

    return EventPopUpMenuButton(
      event: _eventProvider.event,
      onSelected: (value) {
        switch (value) {
          case EventPopUpMenuSelection.refreshGuide:
            _showRefreshGuideDialog();
            break;
          case EventPopUpMenuSelection.createGuideFromEvent:
            _showCreateGuideFromEventDialog(
              Provider.of<CommunityProvider>(context, listen: false),
            );
            break;
          case EventPopUpMenuSelection.duplicateEvent:
            _showDuplicateEventDialog();
            break;
          case EventPopUpMenuSelection.cancelEvent:
            _cancelEvent();
            break;
          case EventPopUpMenuSelection.downloadRegistrationData:
            _downloadRegistrationData();
            break;
          case EventPopUpMenuSelection.downloadChatsAndSuggestions:
            _downloadChatsAndSuggestions();
            break;
        }
      },
      isMobile: isMobile,
    );
  }

  Widget _buildEditEvent() {
    return CircleIconButton(
      color: context.theme.colorScheme.surfaceContainer,
      iconColor: context.theme.colorScheme.onSurface,
      onPressed: () => Dialogs.showAppDrawer(
        context,
        AppDrawerSide.right,
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: context.read<EventPageProvider>(),
            ),
            ChangeNotifierProvider.value(
              value: context.read<EventProvider>(),
            ),
            ChangeNotifierProvider.value(
              value: context.read<CommunityPermissionsProvider>(),
            ),
            ChangeNotifierProvider.value(
              value: context.read<CommunityProvider>(),
            ),
          ],
          child: EditEventDrawer(),
        ),
      ),
      toolTipText: 'Edit event',
      icon: Icons.edit_outlined,
    );
  }

  Widget _buildSettingIcon() {
    return CircleIconButton(
      color: context.theme.colorScheme.surfaceContainer,
      iconColor: context.theme.colorScheme.onSurface,
      onPressed: () => Dialogs.showAppDrawer(
        context,
        AppDrawerSide.right,
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: context.read<CommunityProvider>(),
            ),
            ChangeNotifierProvider.value(
              value: context.read<EventProvider>(),
            ),
          ],
          child: EventSettingsDrawer(
            eventSettingsDrawerType: EventSettingsDrawerType.event,
          ),
        ),
      ),
      toolTipText: 'Event Settings',
      icon: CupertinoIcons.gear_alt,
    );
  }

  ActionButton _buildEnterEvent(DateTime scheduled) {
    const kEventOpenText = 'Enter Event';
    final now = clockService.now();
    final daysDifference = differenceInDays(scheduled, now);
    final difference = scheduled.difference(now);
    String text;
    final externalPlatform = _event.externalPlatform ??
        PlatformItem(platformKey: PlatformKey.community);
    final isPlatformSelectionEnabled =
        CommunityProvider.watch(context).settings.enablePlatformSelection;
    if (daysDifference > 1) {
      text = 'Starts in $daysDifference Days';
    } else if (daysDifference == 1) {
      text = 'Starts Tomorrow';
    } else if (daysDifference == 0 && difference.inMinutes > 9) {
      text = 'Starts in ${durationString(difference)}';
    } else if (daysDifference < 0 || _event.hasEnded(now)) {
      text = 'Event Ended';
    } else {
      text = kEventOpenText;
    }

    final isEventOpen = text == kEventOpenText;

    return ActionButton(
      height: 64,
      type: isEventOpen ? ActionButtonType.filled : ActionButtonType.outline,
      key: EventInfo.enterEventButtonKey,
      expand: true,
      onPressed: isEventOpen
          ? () => alertOnError(context, () async {
                analytics.logEvent(
                  AnalyticsTapEnterEventButtonEvent(
                    communityId: widget.event.communityId,
                    eventId: widget.event.id,
                    templateId: widget.event.templateId,
                    buttonText: text,
                  ),
                  eventTitle: widget.event.title,
                );

                final eventPageProvider = context.read<EventPageProvider>();
                final localEventProvider = EventProvider.read(context);
                JoinEventResults? joinResults;
                if (!localEventProvider.isParticipant) {
                  // Skip the CTA and smart-match dialogs here; enterMeeting
                  // shows both so the order is CTA -> smart match -> enter.
                  joinResults = await widget.onJoinEvent(
                    showConfirm: false,
                    showBreakoutSurveyDialog: false,
                    showPreEventCta: false,
                  );
                  // Re-check the actual participant state in case the join
                  // succeeded but a later step (e.g. the CTA dialog) reported
                  // a failure.
                  if (!joinResults.isJoined &&
                      !localEventProvider.isParticipant) {
                    return;
                  }
                }
                await alertOnError(context, () {
                  if (externalPlatform.platformKey == PlatformKey.community ||
                      !isPlatformSelectionEnabled) {
                    return eventPageProvider.enterMeeting(
                      surveyQuestions: joinResults?.surveyQuestions,
                    );
                  } else {
                    return launch(externalPlatform.url ?? '');
                  }
                });

                final communityId = widget.event.communityId;
                final eventId = widget.event.id;
                final templateId = widget.event.templateId;
                final isHost = (widget.event.eventType != EventType.hostless) &&
                    widget.event.creatorId == userService.currentUserId;
                analytics.logEvent(
                  AnalyticsEnterEventEvent(
                    communityId: communityId,
                    eventId: eventId,
                    asHost: isHost,
                    templateId: templateId,
                  ),
                  eventTitle: widget.event.title,
                );
              })
          : null,
      text: text,
    );
  }

  Widget _buildJoinEventButton() {
    final startTime = widget.event.scheduledTime ?? clockService.now();
    final isLocked = widget.event.isLocked;
    final isEnded = widget.event.isEnded;

    final localEventProvider = _eventProvider;
    final isBanned = localEventProvider.isBanned;
    final canShowFollowCommunity = _canShowFollowCommunity();
    final showRsvpOptInCtas = _showRsvpOptInCtas;

    final showJoinButton = !isBanned &&
        context.read<EventPermissionsProvider>().canJoinEvent &&
        _status != _ParticipantStatus.full;

    final showEnterEventButton = (_isParticipant ||
            (showJoinButton &&
                clockService
                    .now()
                    .isAfter(startTime.subtract(Duration(minutes: 15))))) &&
        !widget.event.hasEnded(clockService.now());
    if (showPrerequisiteWarning) {
      return WarningInfo(
        icon: CircleAvatar(
          radius: 12,
          backgroundColor: context.theme.colorScheme.error,
          child: Icon(
            Icons.school_outlined,
            size: 20,
            color: context.theme.colorScheme.onPrimary,
          ),
        ),
        title: context.l10n.prereqRequired,
      );
    } else if (isBanned) {
      return WarningInfo(
        icon: Icon(
          Icons.info_outline,
          size: 20,
          color: context.theme.colorScheme.error,
        ),
        title: context.l10n.prereqRequired,
        message: context.l10n.removedFromEvent,
      );
    } else if (isEnded) {
      return WarningInfo(
        icon: Icon(
          Icons.info_outline,
          size: 20,
          color: context.theme.colorScheme.error,
        ),
        title: context.l10n.ended,
        message: context.l10n.eventHasEnded,
      );
    } else if (isLocked) {
      return WarningInfo(
        icon: Icon(
          Icons.info_outline,
          size: 20,
          color: context.theme.colorScheme.error,
        ),
        title: context.l10n.locked,
        message: context.l10n.eventIsLocked,
      );
    } else if (showEnterEventButton) {
      return PeriodicBuilder(
        period: Duration(milliseconds: 1000),
        builder: (_) => _buildEnterEvent(startTime),
      );
    } else if (_status == _ParticipantStatus.full) {
      return ActionButton(
        height: 64,
        text: 'FULL',
        expand: true,
      );
    } else if (showJoinButton) {
      return Column(
        children: [
          ActionButton(
            key: EventInfo.rsvpButtonKey,
            height: 64,
            onPressed: () => alertOnError(context, () async {
              analytics.logEvent(
                AnalyticsTapRsvpButtonEvent(
                  communityId: widget.event.communityId,
                  eventId: widget.event.id,
                  templateId: widget.event.templateId,
                ),
                eventTitle: widget.event.title,
              );
              await widget.onJoinEvent(
                joinCommunity: showRsvpOptInCtas
                    ? canShowFollowCommunity
                        ? _joinCommunityDuringRsvp
                        : true
                    : false,
                optInToNewsletters:
                    showRsvpOptInCtas ? _optInToNewsletters : false,
              );
            }),
            expand: true,
            text: 'REGISTER NOW!',
          ),
          if (showRsvpOptInCtas && canShowFollowCommunity) ...[
            SizedBox(height: 10),
            _buildFollowCommunityCheckbox(),
          ],
          if (showRsvpOptInCtas) ...[
            SizedBox(height: 10),
            _buildNewsletterOptInCheckbox(),
          ],
        ],
      );
    } else {
      return SizedBox.shrink();
    }
  }

  Widget _buildAddToCalendar() {
    final event = context.read<EventProvider>().event;

    return CustomStreamBuilder<GetCommunityCalendarLinkResponse>(
      entryFrom: 'EventInfo._buildAddToCalendar',
      showLoading: false,
      // If the calendar link lookup fails, hide the button instead of
      // rendering an error message in the middle of the event card.
      errorBuilder: (_) => SizedBox.shrink(),
      stream: cloudFunctionsEventService
          .getCommunityCalendarLink(
            GetCommunityCalendarLinkRequest(
              eventPath: event.fullPath,
            ),
          )
          .asStream(),
      builder: (context, snapshot) {
        if (snapshot == null) return SizedBox.shrink();
        return CalendarMenuButton(
          onSelected: (selection) {
            switch (selection) {
              case CalendarMenuSelection.google:
                launch(snapshot.googleCalendarLink);
                break;
              case CalendarMenuSelection.office365:
                launch(snapshot.office365CalendarLink);
                break;
              case CalendarMenuSelection.outlook:
                launch(snapshot.outlookCalendarLink);
                break;
              case CalendarMenuSelection.ical:
                _downloadICSfile(snapshot.icsLink);
            }
          },
        );
      },
    );
  }

  Widget _buildCancelEventButton() {
    return ActionButton(
      onPressed: _cancelEvent,
      type: ActionButtonType.outline,
      color: context.theme.colorScheme.surfaceContainerLowest,
      icon: Icon(
        Icons.close,
        size: 20,
        color: context.theme.colorScheme.onSurfaceVariant,
      ),
      text: 'Cancel event',
      textStyle: context.theme.textTheme.bodyMedium!.copyWith(
        color: context.theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildCancelParticipationButton() {
    return ActionButton(
      onPressed: _cancelParticipation,
      type: ActionButtonType.outline,
      color: context.theme.colorScheme.surfaceContainerLowest,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.close,
            size: 20,
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'Cancel',
              style: context.theme.textTheme.bodyMedium!.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventVisibility() {
    final isPublic = _event.isPublic;
    final docPath =
        '${_eventProvider.event.collectionPath}/${_eventProvider.event.id}';
    return CustomStreamBuilder<List<Featured>>(
      entryFrom: '_EventInfoState._buildVisibilityText',
      stream: _featuredStream ??= firestoreDatabase
          .getCommunityFeaturedItems(_eventProvider.communityId),
      showLoading: false,
      builder: (_, featuredItems) {
        final String? text;
        final IconData? icon;

        if (isPublic) {
          if (_canEditEvent) {
            text =
                'Public${featuredItems!.any((f) => f.documentPath == docPath) && _canModerateEvent ? ', Featured' : ''}';
            icon = Icons.public;
          } else {
            text = null;
            icon = null;
          }
        } else {
          text = 'Private';
          icon = Icons.lock_outline;
        }

        // Do not show anything if text is null. Text will be null if user is not admin and
        // the event is public
        if (text == null || icon == null) {
          return SizedBox.shrink();
        }

        return Row(
          children: [
            Tooltip(
              message: isPublic ? 'Public' : 'Private',
              // Material icon rather than media/globe.png and media/lock.png:
              // a baked asset can't take a colour, so these stayed dark beside
              // a label that follows the theme.
              child: Icon(
                icon,
                size: 20,
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: 6),
            HeightConstrainedText(
              text,
              style: context.theme.textTheme.bodyMedium!.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: 20),
          ],
        );
      },
    );
  }

  Widget _buildFollowCommunityCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          activeColor: context.theme.colorScheme.primary,
          checkColor: context.theme.colorScheme.onPrimary,
          value: _joinCommunityDuringRsvp,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _joinCommunityDuringRsvp = value;
              });
            }
          },
        ),
        SizedBox(width: 5),
        Flexible(
          child: Text(
            'Follow ${Provider.of<CommunityProvider>(context).community.name} for access to all events and resources.',
            style: context.theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildNewsletterOptInCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          activeColor: context.theme.colorScheme.primary,
          checkColor: context.theme.colorScheme.onPrimary,
          value: _optInToNewsletters,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _optInToNewsletters = value;
              });
            }
          },
        ),
        SizedBox(width: 5),
        Flexible(
          child: Text(
            'Sign up for the AllSides newsletter.',
            style: context.theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  void _showParticipantsDialog(BuildContext context) {
    ParticipantsDialog(
      eventProvider: EventProvider.read(context),
      eventPermissions: context.read<EventPermissionsProvider>(),
    ).show(context);
  }

  Widget _buildRegisteredEventStatus({
    required bool canAccessParticipantListDetails,
  }) {
    if (!_isParticipant) return const SizedBox.shrink();

    final participantCount = _eventProvider.actualParticipantCount;
    final selfParticipant = _eventProvider.selfParticipant;
    final showReminderText = selfParticipant?.optInToNewsletters ?? false;
    final hasOtherParticipants = participantCount > 1;
    final showAttendeeList = hasOtherParticipants &&
        Provider.of<CommunityProvider>(context)
            .settings
            .showPostRegistrationAttendeeCount;

    Widget statusContent = showAttendeeList
        ? EventPageParticipantsList(
            _event,
            showParticipantCount: false,
            showGoingText: true,
            currentUserFirst: true,
            excludeAvatarSemantics: true,
            allowParticipantsToViewCount: true,
          )
        : Text(
            'You’re going!',
            style: context.theme.textTheme.bodyMedium,
          );

    if (canAccessParticipantListDetails) {
      statusContent = Semantics(
        button: true,
        label: 'Open participants list',
        child: CustomInkWell(
          onTap: () => _showParticipantsDialog(context),
          child: statusContent,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: statusContent),
          if (showReminderText) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'We’ll email you a reminder one hour before the event.',
                textAlign: TextAlign.center,
                style: context.theme.textTheme.bodySmall!.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShareSection() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(20),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final double size;
          final double padding;
          final bool wrapIcons;

          // Five share icons need ~64px each at default size; shrink on narrow cards.
          if (maxWidth < 260) {
            size = 28;
            padding = 2;
            wrapIcons = true;
          } else if (maxWidth < 320) {
            size = 32;
            padding = 4;
            wrapIcons = false;
          } else {
            size = 40;
            padding = 10;
            wrapIcons = false;
          }

          return ShareSection(
            url: _getShareUrl(),
            body: _getShareBody(),
            subject: 'Join my event on ${Environment.appName}!',
            iconColor: context.theme.colorScheme.primary,
            iconBackgroundColor:
                context.theme.colorScheme.surfaceContainerLowest,
            size: size,
            iconSize: min(size - 16, 20),
            buttonPadding: padding,
            wrapIcons: wrapIcons,
            shareCallback: (ShareType type) {
              final communityId = widget.event.communityId;
              final eventId = widget.event.id;
              final templateId = widget.event.templateId;
              analytics.logEvent(
                AnalyticsPressShareEventEvent(
                  communityId: communityId,
                  eventId: eventId,
                  shareType: type,
                  templateId: templateId,
                ),
                eventTitle: widget.event.title,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventPageProvider = context.watch<EventPageProvider>();
    final eventProvider = context.watch<EventProvider>();
    final eventPermissions = Provider.of<EventPermissionsProvider>(context);
    final canCancelParticipation = eventPermissions.canCancelParticipation;
    final canViewCounts = eventPermissions.canViewParticipantCounts;
    final canAccessParticipantListDetails = canViewCounts;
    final showPreRsvpParticipantSummaryRow = !_isParticipant;
    final isMobile = responsiveLayoutService.isMobile(context);

    return Card.outlined(
      color: context.theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            // Specific padding for sides. at 20 iPhone X (375 width) overflows with
            // `Add to calendar` button.
            margin: EdgeInsets.only(left: 19, right: 19, top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VerticalTimeAndDateIndicator(
                      shadow: false,
                      padding: EdgeInsets.only(right: 24),
                      time: DateTime.fromMillisecondsSinceEpoch(
                        (eventProvider
                                .event.scheduledTime?.millisecondsSinceEpoch ??
                            0),
                      ),
                    ),
                    SizedBox(
                      height: isMobile ? 90 : 100,
                      width: isMobile ? 90 : 100,
                      child: CustomStreamBuilder<Template>(
                        entryFrom: '_EventInfoState.build',
                        stream: Provider.of<TemplateProvider>(context)
                            .templateFuture
                            .asStream(),
                        builder: (_, template) => ProxiedImage(
                          eventProvider.event.image ?? template?.image,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    Spacer(),
                    if (_canEditEvent)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildOptionsIcon(),
                          SizedBox(width: 5),
                          _buildSettingIcon(),
                          SizedBox(width: 5),
                          _buildEditEvent(),
                        ],
                      ),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildEventVisibility(),
                    _buildEventTypeName(),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: HeightConstrainedText(
                        _event.title ?? '',
                        maxLines: 3,
                        style: context.theme.textTheme.headlineMedium!.copyWith(
                          // This sits on the card's surfaceContainerLowest, so
                          // it takes the surface pair. The legacy
                          // ThemeData.primaryColor is never configured here and
                          // doesn't track the colour scheme.
                          color: context.theme.colorScheme.onSurface,
                          decoration: _event.status == EventStatus.canceled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                if (eventPageProvider.tags.isNotEmpty) ...[
                  Wrap(
                    children: [
                      for (var tag in eventPageProvider.tags)
                        CommunityTagBuilder(
                          tagDefinitionId: tag.definitionId,
                          builder: (_, isLoading, definition) {
                            if (definition == null) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              '#${definition.title} ',
                              style:
                                  context.theme.textTheme.bodyMedium!.copyWith(
                                color:
                                    context.theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  SizedBox(height: 20),
                ],
                if (showPreRsvpParticipantSummaryRow || _canEditEvent) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: showPreRsvpParticipantSummaryRow
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: CustomInkWell(
                                    onTap: canAccessParticipantListDetails
                                        ? () => _showParticipantsDialog(context)
                                        : null,
                                    child: EventPageParticipantsList(
                                      _event,
                                      showParticipantCount: canViewCounts,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (_canEditEvent)
                          CircleIconButton(
                            onPressed: widget.onMessagePressed,
                            toolTipText: 'Message',
                            icon: CupertinoIcons.paperplane,
                            color: context.theme.colorScheme.surfaceContainer,
                            iconColor: context.theme.colorScheme.onSurface,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                _buildJoinEventButton(),
                _buildRegisteredEventStatus(
                  canAccessParticipantListDetails:
                      canAccessParticipantListDetails,
                ),
                SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (canCancelParticipation || _canEditEvent)
                      Expanded(child: _buildAddToCalendar()),
                    if (canCancelParticipation) ...[
                      SizedBox(width: 8),
                      Expanded(child: _buildCancelParticipationButton()),
                    ] else if (context
                            .watch<EventPermissionsProvider>()
                            .canCancelEvent &&
                        _event.status != EventStatus.canceled) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildCancelEventButton(),
                      ),
                    ],
                  ],
                ),
                if (showPrerequisiteWarning) ...[
                  SizedBox(height: 10),
                  PrerequisiteTemplateWidget(
                    communityId: widget.event.communityId,
                    prerequisiteTemplateId:
                        widget.event.prerequisiteTemplateId!,
                  ),
                ],
              ],
            ),
          ),
          if (!showPrerequisiteWarning) _buildShareSection(),
        ],
      ),
    );
  }

  Widget _buildEventTypeName() {
    final iconColor = context.theme.colorScheme.onSurfaceVariant;

    final String? type;
    final Widget? leading;
    switch (_eventProvider.event.eventType) {
      case EventType.hosted:
        type = null;
        leading = null;
        break;
      case EventType.hostless:
        type = 'Hostless';
        leading = HostlessMark(color: iconColor);
        break;
      case EventType.livestream:
        type = 'Livestream';
        // Near-identical to media/play-screen.png: a rounded frame with a
        // play triangle.
        leading = Icon(
          Icons.smart_display_outlined,
          size: 20,
          color: iconColor,
        );
        break;
    }

    if (type == null || leading == null) {
      return SizedBox.shrink();
    }

    return Row(
      children: [
        leading,
        SizedBox(width: 6),
        Text(
          type,
          style: context.theme.textTheme.bodyMedium!
              .copyWith(color: context.theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
