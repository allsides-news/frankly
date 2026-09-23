import 'dart:async';

import 'package:flutter/material.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/custom_text_field.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/localization/localization_helper.dart';

class FakeParticipantsDialog extends StatefulWidget {
  final int fakeParticipantCount;

  const FakeParticipantsDialog({required this.fakeParticipantCount});

  Future<String?> show() async {
    return showCustomDialog<String>(builder: (_) => this);
  }

  @override
  _FakeParticipantsDialogState createState() => _FakeParticipantsDialogState();
}

class _FakeParticipantsDialogState extends State<FakeParticipantsDialog> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();

    _textController =
        TextEditingController(text: widget.fakeParticipantCount.toString());
  }

  @override
  Widget build(BuildContext context) {
    // Matches SignInDialog: the same surface, radius and hairline border every
    // other dialog uses. This one had grown its own look -- a bright blue
    // 2px frame and its title in a filled tab hanging off the top-left corner.
    return Dialog(
      backgroundColor: context.theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppNeutralColors.of(context).neutral300,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleRow(context),
              SizedBox(height: 16),
              _buildCountField(context),
              SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ActionButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_textController.text),
                  text: 'Save',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HeightConstrainedText(
            'Fake Participants',
            style: context.theme.textTheme.titleLarge,
          ),
        ),
        IconButton(
          icon: Icon(Icons.close),
          color: context.theme.colorScheme.onSurfaceVariant,
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildCountField(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HeightConstrainedText(context.l10n.fakeParticipantCount),
        ),
        SizedBox(width: 16),
        SizedBox(
          width: 80,
          child: CustomTextField(
            controller: _textController,
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    );
  }
}
