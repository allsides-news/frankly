import 'package:flutter/material.dart';

/// A scrolling view whose content fades out at the bottom while there is more
/// to scroll to.
///
/// The fade is a mask on the content's own alpha, not a colour painted over
/// it. Overlaying a colour only disappears where that colour happens to match
/// what's behind: the agenda card draws markdown blocks with their own
/// backgrounds, and the mobile sheet's surface differs from the desktop
/// card's, so any fixed colour read as a grey wash somewhere.
class FadeScrollView extends StatefulWidget {
  final Widget child;
  final double maxFadeExtent;

  /// This value is multiplied by the remaining amount of space in the scroll view to determine the fade extent
  final double fadeScrollScale;

  const FadeScrollView({
    required this.child,
    this.maxFadeExtent = 80.0,
    this.fadeScrollScale = .5,
    Key? key,
  }) : super(key: key);

  @override
  State<FadeScrollView> createState() => _FadeScrollViewState();
}

class _FadeScrollViewState extends State<FadeScrollView> {
  late final ScrollController _controller = ScrollController();

  double get _fadeHeight {
    if (!_controller.hasClients) return 0;
    final distToEnd = _controller.position.maxScrollExtent - _controller.offset;
    return (distToEnd * widget.fadeScrollScale)
        .clamp(0.0, widget.maxFadeExtent);
  }

  @override
  void initState() {
    _controller.addListener(() => setState(() {}));
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 10),
        controller: _controller,
        child: widget.child,
      ),
    );

    if (widget.maxFadeExtent <= 0) return scrollView;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final fade = _fadeHeight;
        // Nothing left to scroll to, or nothing to measure the fade against.
        if (fade <= 0 || !height.isFinite || height <= 0) return scrollView;

        final fadeStart = ((height - fade) / height).clamp(0.0, 1.0);

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Opaque until the fade begins, then ramps to fully transparent,
            // so the content dissolves into whatever is behind it.
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, fadeStart, 1.0],
          ).createShader(rect),
          child: scrollView,
        );
      },
    );
  }
}
