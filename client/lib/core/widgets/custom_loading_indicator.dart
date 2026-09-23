import 'package:client/core/utils/web_utils.dart';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;

// Natural SVG dimensions: 1175×1275 — aspect ratio ~0.922 (width/height).
// Display size chosen to match the visual weight of the replaced CircularProgressIndicator.
const double _kWidth = 48;
const double _kHeight = 52;
const String _kViewType = 'allsides-spin-cycle';

bool _spinnerRegistered = false;

void _ensureSpinnerRegistered() {
  if (_spinnerRegistered) return;
  _spinnerRegistered = true;
  registerWebViewFactory(_kViewType, (int id) {
    return html.ImageElement()
      ..src = 'assets/media/spin-cycle.svg'
      ..alt = ''
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';
  });
}

class CustomLoadingIndicator extends StatelessWidget {
  // color param retained for API compatibility but unused — SVG has fixed brand colours.
  final Color? color;

  const CustomLoadingIndicator({@Deprecated('color has no effect; the SVG uses fixed brand colours') this.color});

  @override
  Widget build(BuildContext context) {
    _ensureSpinnerRegistered();
    return RepaintBoundary(
      child: SizedBox(
        width: _kWidth,
        height: _kHeight,
        child: HtmlElementView(viewType: _kViewType),
      ),
    );
  }
}
