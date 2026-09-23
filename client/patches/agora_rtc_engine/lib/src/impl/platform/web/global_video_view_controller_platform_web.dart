import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_rtc_engine/src/impl/platform/global_video_view_controller_platform.dart';
import 'package:iris_method_channel/iris_method_channel.dart';

// ignore_for_file: public_member_api_docs

const _platformRendererViewType = 'AgoraSurfaceView';

String _getViewType(int id) {
  return 'agora_rtc_engine/${_platformRendererViewType}_$id';
}

class _View {
  _View(int platformViewId)
      : _element = html.DivElement()
          ..id = _getViewType(platformViewId)
          ..style.width = '100%'
          ..style.height = '100%' {
    // Wait until the element is injected into the DOM,
    // see https://github.com/flutter/flutter/issues/143922#issuecomment-1960133128
    _observer = html.IntersectionObserver((_, observer) {
      _tryComplete(observer);
    });
    _observer.observe(_element);

    // IntersectionObserver may never fire when the view stays off-screen,
    // unlaid-out, or hidden — avoid hanging [waitAndGetId] forever.
    _connectionPollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_viewCompleter.isCompleted) {
        _cancelFallbackTimers();
        return;
      }
      if (_element.isConnected == true) {
        _tryComplete(_observer);
      }
    });

    _connectionTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (_viewCompleter.isCompleted) return;
      _cancelFallbackTimers();
      _observer.unobserve(_element);
      _viewCompleter.completeError(
        StateError(
          'AgoraSurfaceView div did not become connected within 10s '
          '(platformViewId=$platformViewId, id=${_element.id})',
        ),
      );
    });
  }

  final html.HtmlElement _element;
  late final html.IntersectionObserver _observer;
  Timer? _connectionPollTimer;
  Timer? _connectionTimeoutTimer;

  html.HtmlElement get element => _element;

  final _viewCompleter = Completer<html.HtmlElement>();

  void _tryComplete(html.IntersectionObserver observer) {
    if (_viewCompleter.isCompleted) return;
    if (_element.isConnected == true) {
      _cancelFallbackTimers();
      observer.unobserve(_element);
      _viewCompleter.complete(_element);
    }
  }

  void _cancelFallbackTimers() {
    _connectionPollTimer?.cancel();
    _connectionPollTimer = null;
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
  }

  /// Stops timers and observer when the view is evicted (e.g. engine teardown)
  /// so periodic/timeout callbacks do not retain [_View] until timeout.
  void dispose() {
    _cancelFallbackTimers();
    _observer.disconnect();
    if (!_viewCompleter.isCompleted) {
      _viewCompleter.completeError(
        StateError('AgoraSurfaceView _View disposed'),
      );
    }
  }

  Future<String> waitAndGetId() async {
    final div = await _viewCompleter.future;
    return div.id;
  }
}

// TODO(littlegnal): Need handle remove view logic on web

class GlobalVideoViewControllerWeb extends GlobalVideoViewControllerPlatfrom {
  /// Web allows only one [ui_web.platformViewRegistry.registerViewFactory] per
  /// view type for the whole app. After [RtcEngine.release] a new
  /// [GlobalVideoViewControllerWeb] is constructed, but Flutter keeps invoking
  /// the *first* registered callback. That callback must write into the same map
  /// that later [setupVideoView] reads, or every reconnect shows "missing _View"
  /// with an empty per-instance map.
  static final Map<int, _View> _viewsByPlatformId = <int, _View>{};
  static bool _agoraSurfaceViewFactoryRegistered = false;

  GlobalVideoViewControllerWeb(
      IrisMethodChannel irisMethodChannel, RtcEngine rtcEngine)
      : super(irisMethodChannel, rtcEngine) {
    if (_agoraSurfaceViewFactoryRegistered) {
      return;
    }
    ui_web.platformViewRegistry.registerViewFactory(_platformRendererViewType,
        (int viewId) {
      final view = _View(viewId);
      _viewsByPlatformId[viewId] = view;
      return view.element;
    });
    _agoraSurfaceViewFactoryRegistered = true;
  }

  @override
  Future<void> detachVideoFrameBufferManager(int irisRtcEngineIntPtr) {
    for (final view in _viewsByPlatformId.values.toList()) {
      view.dispose();
    }
    _viewsByPlatformId.clear();
    return super.detachVideoFrameBufferManager(irisRtcEngineIntPtr);
  }

  @override
  Future<void> setupVideoView(Object viewHandle, VideoCanvas videoCanvas,
      {RtcConnection? connection}) async {
    // The `viewHandle` is the platform view id on web
    final viewId = viewHandle as int;

    final div = _viewsByPlatformId[viewId];
    // Avoid crash when teardown clears the map while setup races (async completion).
    if (div == null) {
      // ignore: avoid_print
      print(
        '[Agora web] setupVideoView: missing _View for platformViewId=$viewId '
        '(map keys=${_viewsByPlatformId.keys.toList()})',
      );
      return;
    }
    final divId = await div.waitAndGetId();

    await super.setupVideoView(divId, videoCanvas, connection: connection);
  }
}
