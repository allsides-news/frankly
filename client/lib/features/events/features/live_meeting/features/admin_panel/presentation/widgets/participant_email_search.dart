import 'package:flutter/material.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/services.dart';
import 'package:data_models/cloud_functions/requests.dart';

class ParticipantEmailSearch extends StatefulWidget {
  const ParticipantEmailSearch({super.key});

  @override
  _ParticipantEmailSearchState createState() => _ParticipantEmailSearchState();
}

class _ParticipantEmailSearchState extends State<ParticipantEmailSearch> {
  final _emailController = TextEditingController();
  LookupEventParticipantByEmailResponse? _result;
  String? _searchedEmail;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _error = null;
      _result = null;
      _searchedEmail = email;
    });

    try {
      final event = EventProvider.read(context).event;
      final result =
          await cloudFunctionsEventService.lookupEventParticipantByEmail(
        LookupEventParticipantByEmailRequest(
          eventPath: event.fullPath,
          email: email,
        ),
      );
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Search failed. Please try again.');
      }
    }
  }

  Widget _buildResults() {
    final result = _result;
    final email = _searchedEmail ?? '';

    if (result == null) return const SizedBox.shrink();

    final registrationLine = result.isRegistered
        ? '1 registration result for this event found for the email \'$email\''
        : '0 results found for the email \'$email\'';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            registrationLine,
            style: TextStyle(fontSize: 13),
          ),
          if (result.isRegistered) ...[
            const SizedBox(height: 4),
            Text(
              '${result.isPresent ? 1 : 0} current event participant${result.isPresent ? '' : 's'} with email \'$email\'',
              style: TextStyle(fontSize: 13),
            ),
            if (result.isPresent && result.currentRoomName != null) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '- User is currently in ${result.currentRoomName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ] else if (result.isPresent) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '- User is currently in the main meeting room',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Participant Search',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  hintText: 'Search by registration email',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            ActionButton(
              text: 'Search',
              onPressed: _search,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          ),
        _buildResults(),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 4),
      ],
    );
  }
}
