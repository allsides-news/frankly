import 'package:client/config/environment.dart';
import 'package:client/core/widgets/section_heading.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/utils/navigation_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({Key? key}) : super(key: key);

  static const _learnMoreUrl =
      'https://www.allsides.com/national-roundtable-collaborators';
  static const _franklyUrl = 'https://frankly.org/';
  static const _livingRoomConversationsUrl =
      'https://livingroomconversations.org/';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTitle(context),
        SizedBox(height: 20),
        _buildDescription(context),
        SizedBox(height: 16),
        _buildLearnMoreButton(context),
      ],
    );
  }

  // Matches the sidebar's "About <app>" link rather than a bare "About",
  // since this section is about the platform, not the current Space.
  Widget _buildTitle(BuildContext context) =>
      SectionHeading('${context.l10n.about} ${Environment.appName}');

  // The copy is localized as fragments around the two inline brand links
  // (before / between / after) because word order differs per locale, e.g.
  // zh needs "提供支持" after the Frankly link and "。" as the closing period.
  Widget _buildDescription(BuildContext context) {
    final l10n = context.l10n;
    final bodyStyle = AppTextStyle.body;
    final linkStyle = bodyStyle.copyWith(decoration: TextDecoration.underline);

    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          TextSpan(
            text: '${l10n.aboutSectionBrandName} ',
            style: bodyStyle.copyWith(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: '${l10n.aboutSectionTagline}\n\n'),
          TextSpan(text: l10n.aboutSectionPoweredBy),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _InlineLink(
              text: 'Frankly',
              url: _franklyUrl,
              style: linkStyle,
            ),
          ),
          TextSpan(text: l10n.aboutSectionDialogueGuides),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _InlineLink(
              text: 'Living Room Conversations',
              url: _livingRoomConversationsUrl,
              style: linkStyle,
            ),
          ),
          TextSpan(text: l10n.aboutSectionClosing),
        ],
      ),
    );
  }

  Widget _buildLearnMoreButton(BuildContext context) {
    return ActionButton(
      type: ActionButtonType.filled,
      // See meeting_guide_card: the filled pair has to move together.
      color: context.theme.colorScheme.primary,
      textColor: context.theme.colorScheme.onPrimary,
      minWidth: 0,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      borderRadius: BorderRadius.circular(8),
      onPressed: () => launch(_learnMoreUrl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HeightConstrainedText(
            context.l10n.learnMore,
            style: context.theme.textTheme.bodyMedium!.copyWith(
              color: context.theme.colorScheme.onPrimary,
            ),
          ),
          SizedBox(width: 8),
          FaIcon(
            FontAwesomeIcons.arrowUpRightFromSquare,
            size: 16,
            color: context.theme.colorScheme.onPrimary,
          ),
        ],
      ),
    );
  }
}

/// A [TextSpan]-embedded link that, unlike a plain `TapGestureRecognizer`,
/// can receive keyboard focus and be activated with Enter/Space -- needed
/// for WCAG 2.1 keyboard-operability on Flutter web.
class _InlineLink extends StatefulWidget {
  final String text;
  final String url;
  final TextStyle style;

  const _InlineLink({
    required this.text,
    required this.url,
    required this.style,
  });

  @override
  State<_InlineLink> createState() => _InlineLinkState();
}

class _InlineLinkState extends State<_InlineLink> {
  bool _isFocused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isActivationKey = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space;
    if (event is KeyDownEvent && isActivationKey) {
      launch(widget.url);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: () => launch(widget.url),
          child: Semantics(
            link: true,
            label: widget.text,
            child: Container(
              decoration: _isFocused
                  ? BoxDecoration(
                      border: Border.all(
                        color: context.theme.colorScheme.primary,
                      ),
                    )
                  : null,
              child: Text(widget.text, style: widget.style),
            ),
          ),
        ),
      ),
    );
  }
}
