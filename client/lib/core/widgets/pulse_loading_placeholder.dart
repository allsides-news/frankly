import 'package:flutter/material.dart';

class PulseLoadingPlaceholder extends StatefulWidget {
  const PulseLoadingPlaceholder({
    super.key,
    this.height = 120,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final double height;
  final double? width;
  final BorderRadiusGeometry borderRadius;

  @override
  State<PulseLoadingPlaceholder> createState() =>
      _PulseLoadingPlaceholderState();
}

class _PulseLoadingPlaceholderState extends State<PulseLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 900),
    vsync: this,
  );

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.25,
    end: 0.5,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFA1A1A1),
        borderRadius: widget.borderRadius,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return Opacity(
        opacity: 0.5,
        child: _buildPlaceholder(),
      );
    }

    return FadeTransition(
      opacity: _opacity,
      child: _buildPlaceholder(),
    );
  }
}
