import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DataPrivacyNotice extends StatelessWidget {
  final bool compact;

  const DataPrivacyNotice({
    Key? key,
    this.compact = false,
  }) : super(key: key);

  static const _privacyNoticeUrl = 'https://www.allsides.com/privacy';
  static const _roundtableReportsUrl = 'https://www.allsides.com/roundtables';
  static const _feedbackEmail = 'feedback@allsides.com';

  @override
  Widget build(BuildContext context) {
    // The AV check panel is `surface` now, so its text is onSurface.
    final textColor = context.theme.colorScheme.onSurface;
    final bodyStyle = AppTextStyle.body.copyWith(
      color: textColor,
      height: compact ? 1.22 : 1.18,
    );
    final titleStyle = AppTextStyle.headline3.copyWith(color: textColor);
    final spacing = compact ? 16.0 : 20.0;
    final sectionSpacing = compact ? 26.0 : 32.0;
    final linkSpacing = compact ? 10.0 : 12.0;

    return Semantics(
      container: true,
      label: 'Reminder and data privacy information',
      child: DefaultTextStyle(
        style: bodyStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reminder', style: titleStyle),
            SizedBox(height: compact ? 10 : 14),
            _PrivacyPoint(
              title: 'Everyone around the table is equal.',
              body:
                  'This is a space for acknowledgement, respect, and curiosity.',
              bodyStyle: bodyStyle,
            ),
            SizedBox(height: sectionSpacing),
            Text('Data & Privacy', style: titleStyle),
            SizedBox(height: compact ? 12 : 16),
            _PrivacyPoint(
              title: 'Audio and video recordings will be deleted.',
              body:
                  'We initially record audio and video for analysis and verification, and delete as soon as possible (generally under a week).',
              bodyStyle: bodyStyle,
            ),
            SizedBox(height: spacing),
            _PrivacyPoint(
              title: 'All recorded data is de-identified.',
              body:
                  'Your data can’t be tracked back to you. Only AllSides and Roundtable Hosts can access recordings.',
              bodyStyle: bodyStyle,
            ),
            SizedBox(height: spacing),
            _PrivacyPoint(
              title:
                  'Quotes from your discussion may appear in a published Roundtable Report.',
              body:
                  'AllSides may feature de-identified quotes and findings in future content.',
              bodyStyle: bodyStyle,
            ),
            SizedBox(height: spacing),
            _PrivacyPoint(
              title: 'Conversation guides may be developed with partners.',
              body:
                  'When applicable, partner organizations involved in the guide are named in the event description.',
              bodyStyle: bodyStyle,
            ),
            SizedBox(height: spacing),
            _PrivacyPoint(
              title: 'We don’t sell your data.',
              body: 'We value your trust more than profits.',
              bodyStyle: bodyStyle,
            ),
            SizedBox(height: compact ? 28 : 36),
            _InteractiveLink(
              text: 'Read our full Privacy Notice.',
              url: _privacyNoticeUrl,
              style: bodyStyle,
            ),
            SizedBox(height: linkSpacing),
            _InteractiveLink(
              text: 'Read recent Roundtable Reports.',
              url: _roundtableReportsUrl,
              style: bodyStyle,
            ),
            SizedBox(height: linkSpacing),
            _InteractiveLink(
              text: 'Send questions to $_feedbackEmail.',
              url: 'mailto:$_feedbackEmail',
              style: bodyStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  final String title;
  final String body;
  final TextStyle bodyStyle;

  const _PrivacyPoint({
    Key? key,
    required this.title,
    required this.body,
    required this.bodyStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          TextSpan(
            text: '$title\n',
            style: bodyStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: body,
            style: bodyStyle.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveLink extends StatelessWidget {
  final String text;
  final String url;
  final TextStyle style;

  const _InteractiveLink({
    Key? key,
    required this.text,
    required this.url,
    required this.style,
  }) : super(key: key);

  Future<void> _openLink() async {
    await launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _openLink,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.zero,
        foregroundColor: style.color,
        textStyle: style.copyWith(
          fontStyle: FontStyle.italic,
          decoration: TextDecoration.underline,
          decorationColor: style.color,
        ),
      ),
      child: Text(
        text,
        style: style.copyWith(
          fontStyle: FontStyle.italic,
          decoration: TextDecoration.underline,
          decorationColor: style.color,
        ),
      ),
    );
  }
}
