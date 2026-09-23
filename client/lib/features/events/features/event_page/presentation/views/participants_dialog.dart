import 'package:client/styles/styles.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_list_view.dart';
import 'package:client/features/user/presentation/widgets/user_profile_chip.dart';
import 'package:client/services.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/event.dart';
import 'package:provider/provider.dart';

class ParticipantsDialog extends StatelessWidget {
  final EventProvider eventProvider;
  final EventPermissionsProvider eventPermissions;

  const ParticipantsDialog({
    required this.eventProvider,
    required this.eventPermissions,
  });

  Event get event => eventProvider.event;

  Future<bool> show(BuildContext context) async {
    final communityProvider =
        Provider.of<CommunityProvider>(context, listen: false);
    return (await showCustomDialog(
          builder: (context) => InheritedProvider.value(
            value: communityProvider,
            child: this,
          ),
        )) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: eventProvider,
      builder: (context, _) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {},
                child: eventProvider.useParticipantCountEstimate
                    ? _buildLivestreamEventLayout(context)
                    : _buildRegularEventLayout(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLivestreamEventLayout(BuildContext context) {
    // Ensure the participant stream is initialized for hostless/livestream
    // events that normally use participant count estimates.
    final _ = eventProvider.actualParticipantCount;
    final participantStream = eventProvider.eventParticipantsStream;

    return Container(
      constraints: BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: context.theme.colorScheme.surfaceContainerLowest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<List<Participant>>(
          stream: participantStream,
          initialData: eventProvider.eventParticipants,
          builder: (context, snapshot) {
            final participants =
                snapshot.data ?? eventProvider.eventParticipants;
            final l10n = appLocalizationService.getLocalization();

            return CustomListView(
              shrinkWrap: true,
              children: [
                _buildCloseDialogIcon(context),
                _buildDialogTitle(context),
                if (snapshot.hasError)
                  HeightConstrainedText(l10n.participantsLoadError)
                else if (participants.isEmpty)
                  HeightConstrainedText(l10n.noOneIsHereYet)
                else
                  ..._buildEventParticipants(context, participants),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRegularEventLayout(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 400),
      child: CustomListView(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: context.theme.colorScheme.surfaceContainerLowest,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: CustomListView(
                shrinkWrap: true,
                children: [
                  _buildCloseDialogIcon(context),
                  _buildDialogTitle(context),
                  ..._buildEventParticipants(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseDialogIcon(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ActionButton(
        height: 40,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.zero,
        minWidth: 50,
        borderRadius: BorderRadius.circular(0),
        color: Colors.transparent,
        icon: Icon(
          Icons.close,
          size: 40,
          color: context.theme.colorScheme.primary,
        ),
        onPressed: () => Navigator.of(context).pop(false),
      ),
    );
  }

  Widget _buildDialogTitle(BuildContext context) {
    final l10n = appLocalizationService.getLocalization();
    // Use actualParticipantCount to get real count from stream
    // even for hostless/livestream events that normally use estimates
    final count = eventProvider.actualParticipantCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HeightConstrainedText(
        l10n.participantCount(count),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: context.theme.colorScheme.primary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  List<Widget> _buildEventParticipants(
    BuildContext context, [
    List<Participant>? participants,
  ]) {
    final participantsList =
        (participants ?? eventProvider.eventParticipants).toList();
    final creator =
        participantsList.firstWhereOrNull((p) => p.id == event.creatorId);
    final self = participantsList.firstWhereOrNull(
      (p) => p.id == Provider.of<UserService>(context).currentUserId,
    );

    // Prioritize the current user, then creator, while avoiding duplicates.
    final prioritizedParticipants = <Participant>[];
    final prioritizedParticipantIds = <String>{};

    for (final participant in [self, creator].whereType<Participant>()) {
      if (prioritizedParticipantIds.add(participant.id)) {
        prioritizedParticipants.add(participant);
      }
    }

    participantsList
        .removeWhere((p) => prioritizedParticipantIds.contains(p.id));
    participantsList.insertAll(0, prioritizedParticipants);

    return [
      for (final p in participantsList) _buildParticipant(p, context),
    ];
  }

  Widget _buildParticipant(Participant participant, BuildContext context) {
    return _Participant(
      id: participant.id,
      isRemoveAllowed:
          eventPermissions.canRemoveParticipant(participant) && !event.isLocked,
      onRemove: () => alertOnError(
        context,
        () => eventProvider.cancelParticipation(
          participantId: participant.id,
        ),
      ),
    );
  }
}

class _Participant extends StatelessWidget {
  final String? id;
  final bool isRemoveAllowed;
  final Function() onRemove;

  const _Participant({
    required this.id,
    required this.isRemoveAllowed,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: UserProfileChip(userId: id)),
          if (isRemoveAllowed)
            CustomInkWell(
              onTap: onRemove,
              boxShape: BoxShape.circle,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.close, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}
