import 'package:flutter/material.dart';

class DelayedLoadingPlaceholder extends StatefulWidget {
  const DelayedLoadingPlaceholder({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 600),
  });

  final Widget child;
  final Duration delay;

  @override
  State<DelayedLoadingPlaceholder> createState() =>
      _DelayedLoadingPlaceholderState();
}

class _DelayedLoadingPlaceholderState extends State<DelayedLoadingPlaceholder> {
  bool _showPlaceholder = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _showPlaceholder = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showPlaceholder) return const SizedBox.shrink();

    return widget.child;
  }
}
