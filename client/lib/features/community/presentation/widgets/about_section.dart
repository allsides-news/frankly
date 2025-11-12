import 'package:flutter/material.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/html_content.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/community/community.dart';
import 'package:client/core/localization/localization_helper.dart';

/// Section of the CommunityHomePage with a description of the community. It constrains the description
/// to a certain size and, if the text overflows, allows the user to expand the widget to see more
class CommunityHomeAboutSection extends StatefulWidget {
  final Community community;

  const CommunityHomeAboutSection({
    required this.community,
    Key? key,
  }) : super(key: key);

  @override
  State<CommunityHomeAboutSection> createState() => _AboutWidgetState();
}

class _AboutWidgetState extends State<CommunityHomeAboutSection> {
  static const maxDescriptionLength = 160;
  bool _isExpanded = false;

  @override
  void initState() {
    _isExpanded = false;

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = context.theme.textTheme.bodyMedium;
    final titleStyle = context.theme.textTheme.titleMedium;
    final hasLongDescription = widget.community.description != null &&
        widget.community.description!.length > maxDescriptionLength;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeightConstrainedText(context.l10n.aboutUs, style: titleStyle),
        SizedBox(height: 10),
        if (isNullOrEmpty(widget.community.description))
          Text(
            context.l10n.sectionNotFilledYet,
            textAlign: TextAlign.left,
            style: textStyle,
          )
        else
          HtmlContent(
            widget.community.description!,
            style: textStyle,
            textAlign: TextAlign.left,
            maxLines: hasLongDescription && !_isExpanded ? 5 : null,
            overflow: hasLongDescription && !_isExpanded ? TextOverflow.ellipsis : null,
          ),
        SizedBox(height: 10),
        if (!_isExpanded && hasLongDescription)
          CustomInkWell(
            child: HeightConstrainedText(
              'Read More',
              style: textStyle,
            ),
            onTap: () => setState(() => _isExpanded = true),
          ),
        if (_isExpanded && hasLongDescription)
          CustomInkWell(
            child: HeightConstrainedText(
              'Less',
              style: textStyle,
            ),
            onTap: () => setState(() => _isExpanded = false),
          ),
      ],
    );
  }
}
