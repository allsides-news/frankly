// Copyright 2022 Sarbagya Dhaubanjar. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'dart:ui_web' as ui_web;

/// Only accept postMessage payloads from embedded YouTube iframes, not arbitrary
/// same-context scripts spoofing JSON or channel metadata.
bool _trustedYoutubeIframeMessageOrigin(MessageEvent event) {
  final origin = event.origin;
  if (origin.isEmpty) return false;
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.scheme != 'https') return false;
  const trustedHosts = {
    'www.youtube.com',
    'youtube.com',
    'www.youtube-nocookie.com',
    'youtube-nocookie.com',
  };
  return trustedHosts.contains(uri.host);
}

/// An implementation of [PlatformWebViewControllerCreationParams] using Flutter
/// for Web API.
@immutable
class WebYoutubePlayerIframeControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  /// Creates a [WebYoutubePlayerIframeControllerCreationParams] instance based on [PlatformWebViewControllerCreationParams].
  WebYoutubePlayerIframeControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewControllerCreationParams params,
  );

  static int _nextIFrameId = 0;

  /// The underlying element used as the WebView.
  @visibleForTesting
  final IFrameElement ytiFrame = IFrameElement()
    ..id = 'youtube-${_nextIFrameId++}'
    ..width = '100%'
    ..height = '100%'
    ..style.border = 'none'
    ..allow = 'autoplay;fullscreen';
}

/// An implementation of [PlatformWebViewController] using Flutter for Web API.
class WebYoutubePlayerIframeController extends PlatformWebViewController {
  /// Constructs a [WebYoutubePlayerIframeController].
  WebYoutubePlayerIframeController(
    PlatformWebViewControllerCreationParams params,
  ) : super.implementation(
          params is WebYoutubePlayerIframeControllerCreationParams
              ? params
              : WebYoutubePlayerIframeControllerCreationParams
                  .fromPlatformWebViewControllerCreationParams(params),
        );

  WebYoutubePlayerIframeControllerCreationParams get _params {
    return params as WebYoutubePlayerIframeControllerCreationParams;
  }

  late final JavaScriptChannelParams _javaScriptChannelParams;
  bool _isJavaScriptChannelReady = false;

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) {
    _params.ytiFrame.srcdoc = html;

    // Fallback for browser that doesn't support srcdoc.
    _params.ytiFrame.src = Uri.dataFromString(
      html,
      mimeType: 'text/html',
      encoding: utf8,
    ).toString();

    return SynchronousFuture(null);
  }

  @override
  Future<void> runJavaScript(String javaScript) {
    final function = javaScript.replaceAll('"', '<<quote>>');
    _params.ytiFrame.contentWindow?.postMessage(
      '{"key": null, "function": "$function"}',
      '*',
    );

    return SynchronousFuture(null);
  }

  @override
  Future<String> runJavaScriptReturningResult(String javaScript) async {
    final contentWindow = _params.ytiFrame.contentWindow;
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    final function = javaScript.replaceAll('"', '<<quote>>');

    final completer = Completer<String>();

    // Add timeout to prevent indefinite hanging
    final timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('JavaScript execution timed out after 10 seconds'),
        );
      }
    });

    final subscription = window.onMessage.listen(
      (event) {
        if (!_trustedYoutubeIframeMessageOrigin(event)) return;
        if (event.data is! String) return;
        dynamic data;
        try {
          data = jsonDecode(event.data as String);
        } catch (_) {
          return;
        }

        if (data is Map && data.containsKey(key)) {
          timeoutTimer.cancel();
          completer.complete(data[key].toString());
        }
      },
    );

    contentWindow?.postMessage(
      '{"key": "$key", "function": "$function"}',
      '*',
    );

    try {
      return await completer.future;
    } finally {
      timeoutTimer.cancel();
      await subscription.cancel();
    }
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    _javaScriptChannelParams = javaScriptChannelParams;
    _isJavaScriptChannelReady = true;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    // no-op
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    // no-op
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    // no-op
  }

  @override
  Future<void> enableZoom(bool enabled) async {
    // no-op
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    // no-op
  }
}

/// An implementation of [PlatformWebViewWidget] using Flutter the for Web API.
class YoutubePlayerIframeWeb extends PlatformWebViewWidget {
  /// Constructs a [YoutubePlayerIframeWeb].
  YoutubePlayerIframeWeb(PlatformWebViewWidgetCreationParams params)
      : _controller = params.controller as WebYoutubePlayerIframeController,
        super.implementation(params) {
    ui_web.platformViewRegistry.registerViewFactory(
      _controller._params.ytiFrame.id,
      (int viewId) => _controller._params.ytiFrame,
    );
  }

  final WebYoutubePlayerIframeController _controller;

  @override
  Widget build(BuildContext context) {
    return _YoutubeIframeHtmlElementView(
      platformKey: params.key,
      controller: _controller,
      viewType: _controller._params.ytiFrame.id,
    );
  }
}

// window.onMessage: cancel before rebinding when HtmlElementView is recreated; dispose drops the last subscription.
class _YoutubeIframeHtmlElementView extends StatefulWidget {
  const _YoutubeIframeHtmlElementView({
    required this.platformKey,
    required this.controller,
    required this.viewType,
  });

  final Key? platformKey;
  final WebYoutubePlayerIframeController controller;
  final String viewType;

  @override
  State<_YoutubeIframeHtmlElementView> createState() =>
      _YoutubeIframeHtmlElementViewState();
}

class _YoutubeIframeHtmlElementViewState
    extends State<_YoutubeIframeHtmlElementView> {
  StreamSubscription<MessageEvent>? _youtubeMessageSubscription;

  @override
  void dispose() {
    _youtubeMessageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      key: widget.platformKey,
      viewType: widget.viewType,
      onPlatformViewCreated: (_) {
        void attachYoutubeListener([int attemptsRemaining = 64]) {
          if (!mounted) return;
          if (!widget.controller._isJavaScriptChannelReady) {
            if (attemptsRemaining <= 0) return;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => attachYoutubeListener(attemptsRemaining - 1),
            );
            return;
          }
          final channelParams = widget.controller._javaScriptChannelParams;
          _youtubeMessageSubscription?.cancel();
          _youtubeMessageSubscription = window.onMessage.listen(
            (event) {
              if (!mounted) return;
              if (!_trustedYoutubeIframeMessageOrigin(event)) return;
              if (event.data is! String) return;
              if (channelParams.name == 'YoutubePlayer') {
                channelParams.onMessageReceived(
                  JavaScriptMessage(message: event.data as String),
                );
              }
            },
          );
        }

        attachYoutubeListener();
      },
    );
  }
}
