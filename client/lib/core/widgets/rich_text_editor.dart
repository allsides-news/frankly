import 'package:flutter/material.dart';
import 'package:client/styles/styles.dart';

/// A rich text editor widget with a formatting toolbar
/// Supports bold, italic, headings, paragraphs, and basic HTML
class RichTextEditor extends StatefulWidget {
  final String? labelText;
  final String? initialValue;
  final Function(String)? onChanged;
  final int minLines;
  final int maxLines;

  const RichTextEditor({
    Key? key,
    this.labelText,
    this.initialValue,
    this.onChanged,
    this.minLines = 4,
    this.maxLines = 10,
  }) : super(key: key);

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _wrapSelection(String prefix, String suffix) {
    final text = _controller.text;
    final selection = _controller.selection;
    
    if (selection.start == -1 || selection.end == -1) {
      return;
    }

    final selectedText = text.substring(selection.start, selection.end);
    final newText = text.substring(0, selection.start) +
        prefix +
        selectedText +
        suffix +
        text.substring(selection.end);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length + suffix.length,
      ),
    );

    widget.onChanged?.call(newText);
  }

  void _insertText(String textToInsert) {
    final text = _controller.text;
    final selection = _controller.selection;
    
    if (selection.start == -1) {
      return;
    }

    final newText = text.substring(0, selection.start) +
        textToInsert +
        text.substring(selection.end);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + textToInsert.length,
      ),
    );

    widget.onChanged?.call(newText);
  }

  void _applyHeading(int level) {
    final text = _controller.text;
    final selection = _controller.selection;
    
    if (selection.start == -1 || selection.end == -1) {
      return;
    }

    final selectedText = text.substring(selection.start, selection.end);
    final headingTag = 'h$level';
    final wrappedText = '<$headingTag>$selectedText</$headingTag>';
    
    final newText = text.substring(0, selection.start) +
        wrappedText +
        text.substring(selection.end);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + wrappedText.length),
    );

    widget.onChanged?.call(newText);
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: context.theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: context.theme.colorScheme.outline.withOpacity(0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _buildToolbarButton(
            icon: Icons.format_bold,
            tooltip: 'Bold',
            onPressed: () => _wrapSelection('<strong>', '</strong>'),
          ),
          _buildToolbarButton(
            icon: Icons.format_italic,
            tooltip: 'Italic',
            onPressed: () => _wrapSelection('<em>', '</em>'),
          ),
          _buildToolbarButton(
            icon: Icons.format_underlined,
            tooltip: 'Underline',
            onPressed: () => _wrapSelection('<u>', '</u>'),
          ),
          const SizedBox(width: 8),
          _buildToolbarButton(
            icon: Icons.title,
            tooltip: 'Heading 1',
            onPressed: () => _applyHeading(1),
          ),
          _buildToolbarButton(
            icon: Icons.format_size,
            tooltip: 'Heading 2',
            onPressed: () => _applyHeading(2),
          ),
          const SizedBox(width: 8),
          _buildToolbarButton(
            icon: Icons.format_list_bulleted,
            tooltip: 'Bullet List',
            onPressed: () => _wrapSelection('<ul><li>', '</li></ul>'),
          ),
          _buildToolbarButton(
            icon: Icons.format_list_numbered,
            tooltip: 'Numbered List',
            onPressed: () => _wrapSelection('<ol><li>', '</li></ol>'),
          ),
          const SizedBox(width: 8),
          _buildToolbarButton(
            icon: Icons.link,
            tooltip: 'Insert Link',
            onPressed: () => _showLinkDialog(),
          ),
          _buildToolbarButton(
            icon: Icons.image,
            tooltip: 'Insert Image',
            onPressed: () => _showImageDialog(),
          ),
        ],
      ),
    );
  }

  void _showLinkDialog() {
    final textController = TextEditingController();
    final urlController = TextEditingController();
    
    final selection = _controller.selection;
    if (selection.start != -1 && selection.end != -1 && selection.start != selection.end) {
      textController.text = _controller.text.substring(selection.start, selection.end);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Insert Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: InputDecoration(
                labelText: 'Link Text',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: 'URL',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.isNotEmpty && urlController.text.isNotEmpty) {
                final linkHtml = '<a href="${urlController.text}">${textController.text}</a>';
                _insertText(linkHtml);
              }
              Navigator.pop(context);
            },
            child: Text('Insert'),
          ),
        ],
      ),
    );
  }

  void _showImageDialog() {
    final urlController = TextEditingController();
    final altController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Insert Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: 'Image URL',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: altController,
              decoration: InputDecoration(
                labelText: 'Alt Text (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                final altText = altController.text.isNotEmpty ? altController.text : 'Image';
                final imgHtml = '<img src="${urlController.text}" alt="$altText" />';
                _insertText(imgHtml);
              }
              Navigator.pop(context);
            },
            child: Text('Insert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.labelText!,
              style: AppTextStyle.bodySmall.copyWith(
                color: _hasFocus
                    ? context.theme.colorScheme.primary
                    : context.theme.colorScheme.onSurfaceVariant,
                fontWeight: _hasFocus ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _hasFocus
                  ? context.theme.colorScheme.primary
                  : context.theme.colorScheme.onPrimaryContainer,
              width: _hasFocus ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            children: [
              _buildToolbar(),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                minLines: widget.minLines,
                keyboardType: TextInputType.multiline,
                style: context.theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  hintText: 'Enter description (HTML supported)...',
                  hintStyle: context.theme.textTheme.bodyMedium?.copyWith(
                    color: context.theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                onChanged: widget.onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

