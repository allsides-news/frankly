import 'package:flutter/material.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/custom_list_view.dart';
import 'package:client/core/widgets/custom_text_field.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/widgets/height_constained_text.dart';

class ConfirmTextInputDialogue extends StatefulWidget {
  final String title;
  final String mainText;
  final String subText;
  final String confirmText;
  final Function(BuildContext context, String input)? onConfirm;
  final String cancelText;
  final Function(BuildContext context)? onCancel;
  final String textLabel;
  final String textHint;

  const ConfirmTextInputDialogue({
    this.title = '',
    this.mainText = '',
    this.subText = '',
    this.confirmText = 'Confirm',
    this.onConfirm,
    this.cancelText = 'Cancel',
    this.onCancel,
    required this.textLabel,
    this.textHint = '',
  });

  Future<String?> show({BuildContext? context}) async {
    return (await showCustomDialog(builder: (_) => this));
  }

  @override
  State<ConfirmTextInputDialogue> createState() =>
      _ConfirmTextInputDialogueState();
}

class _ConfirmTextInputDialogueState extends State<ConfirmTextInputDialogue> {
  String _textInput = '';

  void _cancel() {
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      onCancel(context);
    } else {
      Navigator.of(context).pop(null);
    }
  }

  void _confirm() {
    final onConfirm = widget.onConfirm;
    if (onConfirm != null) {
      onConfirm(context, _textInput);
    } else {
      Navigator.of(context).pop(_textInput);
    }
  }

  Widget _buildDialog(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {},
        child: Stack(
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: 600),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: context.theme.colorScheme.primary,
              ),
              padding: const EdgeInsets.all(40),
              child: CustomListView(
                shrinkWrap: true,
                children: [
                  // Add top padding to prevent title from overlapping with X button
                  SizedBox(height: 10),
              if (!isNullOrEmpty(widget.title)) ...[
                HeightConstrainedText(
                  widget.title,
                  style: AppTextStyle.headline1
                      .copyWith(color: context.theme.colorScheme.onPrimary),
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 20),
              ],
              if (!isNullOrEmpty(widget.mainText)) ...[
                HeightConstrainedText(
                  widget.mainText,
                  style: AppTextStyle.body
                      .copyWith(color: context.theme.colorScheme.onPrimary),
                  textAlign: TextAlign.left,
                ),
                SizedBox(height: 10),
              ],
              if (!isNullOrEmpty(widget.subText)) ...[
                HeightConstrainedText(
                  widget.subText,
                  style: AppTextStyle.body
                      .copyWith(color: context.theme.colorScheme.onPrimary),
                  textAlign: TextAlign.left,
                ),
                SizedBox(height: 10),
              ],
              CustomTextField(
                labelText: widget.textLabel,
                hintText: widget.textHint,
                initialValue: '',
                onChanged: (value) => setState(() => _textInput = value),
                minLines: 2,
                maxLines: 2,
                // Make cursor white/light for visibility on black background
                cursorColor: context.theme.colorScheme.onPrimary,
                // Ensure text is visible
                textStyle: AppTextStyle.body
                    .copyWith(color: context.theme.colorScheme.onPrimary),
                // Make hint/placeholder text lighter and visible
                hintStyle: AppTextStyle.body.copyWith(
                  color: context.theme.colorScheme.onPrimary.withOpacity(0.5),
                ),
                // Make label text lighter
                labelStyle: AppTextStyle.bodySmall.copyWith(
                  color: context.theme.colorScheme.onPrimary.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isNullOrEmpty(widget.cancelText))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ActionButton(
                          type: ActionButtonType.outline,
                          height: 55,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          minWidth: 100,
                          color: Colors.transparent,
                          text: widget.cancelText,
                          // Use textColor property for proper foreground color
                          textColor: context.theme.colorScheme.onPrimary,
                          textStyle: AppTextStyle.body,
                          borderSide: BorderSide(
                            color: context.theme.colorScheme.onPrimary,
                            width: 2,
                          ),
                          onPressed: _cancel,
                        ),
                      ),
                    )
                  else
                    SizedBox.shrink(),
                  Expanded(
                    child: ActionButton(
                      height: 55,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      color: context.theme.colorScheme.onPrimary,
                      disabledColor: context.theme.colorScheme.onPrimary.withOpacity(0.5),
                      text: widget.confirmText,
                      // Use textColor property for proper foreground color
                      textColor: context.theme.colorScheme.primary,
                      textStyle: AppTextStyle.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      onPressed: (_textInput.trim().isNotEmpty) ? _confirm : null,
                    ),
                  ),
                ],
              ),
                ],
              ),
            ),
            // Close button (X) positioned at actual top-right corner of modal
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: context.theme.colorScheme.onPrimary,
                  size: 24,
                ),
                onPressed: _cancel,
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Builder(
        builder: (context) => _buildDialog(context),
      ),
    );
  }
}
