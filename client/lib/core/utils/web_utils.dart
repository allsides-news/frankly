@JS()
library web_utils;

import 'dart:ui_web' as ui_web;

import 'package:client/core/utils/check_can_autoplay_future.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:cloud_functions_web/cloud_functions_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:js/js.dart';
import 'package:client/core/utils/driver_binding.dart';
import 'package:client/core/utils/custom_path_url_strategy.dart';
import 'package:platform_detect/platform_detect.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:timezone/browser.dart' as tz;
import 'package:universal_html/html.dart' as html;
import 'package:universal_html/js.dart' as universal_js;

@JS()
external dynamic checkCanAutoplay();

Future<bool> checkCanAutoplayFuture() =>
    checkCanAutoplayFutureFromExternal(checkCanAutoplay);

String? getTimezone() {
  final timeZoneObject = universal_js.context['Intl']
      ?.callMethod('DateTimeFormat')
      ?.callMethod('resolvedOptions');

  return timeZoneObject != null ? timeZoneObject['timeZone'] as String : null;
}

var _initialized = false;
Future<void> initializeTimezones() {
  return swallowErrors(() async {
    final prefix = Uri.base.host.contains('localhost') ? '' : 'assets/';
    await tz.initializeTimeZone('${prefix}assets/latest_all.tzf');
    _initialized = true;
  });
}

String? getTimezoneAbbreviation(DateTime time) {
  if (!_initialized) return '';

  return swallowErrorsSync(() {
        final location = tz.getLocation(getTimezone() ?? '');
        return tz.TZDateTime.from(time, location).timeZone.abbreviation;
      }) ??
      '';
}

void setURLPathStrategy() {
  setUrlStrategy(CustomPathUrlStrategy());
}

void enableDriverBinding() {
  DriverBinding();
}

// WKWebview is an embedded web view in apps. NOTE: this flag will return
// true for Chrome browser in iOS.
bool get isWKWebView => browser.isWKWebView;

class CustomPointerInterceptor extends StatelessWidget {
  final Widget child;

  const CustomPointerInterceptor({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(child: child);
  }
}

void registerWebViewFactory(String key, html.Element Function(int) factory) {
  ui_web.platformViewRegistry.registerViewFactory(key, factory);
}

HttpsCallablePlatform? getHttpsCallableWeb(String functionName) {
  final callable = FirebaseFunctionsWeb(
    region: 'us-central1',
    app: FirebaseFunctionsWeb.instance.app,
  ).httpsCallable(null, functionName, HttpsCallableOptions());

  return callable;
}

void stopMediaTrack(html.MediaStreamTrack track) {
  track.stop();
}

class BrowserCompatibilityResult {
  final bool isCompatible;
  final String? message;

  const BrowserCompatibilityResult({
    required this.isCompatible,
    this.message,
  });
}

/// Checks whether the current browser meets minimum version requirements
/// for Agora SDK compatibility.
BrowserCompatibilityResult checkBrowserCompatibility() {
  const warningMessage =
      'Your browser may not fully support this experience. '
      'We recommend using the latest version of Chrome or Firefox.';

  // Minimum versions based on Agora SDK + canvas.captureStream() requirements.
  // Safari requires special handling: captureStream() was added in 16.4,
  // so a major-only check of 16 would incorrectly pass 16.0–16.3.
  const minMajorVersions = {
    'Chrome': 90,
    'Firefox': 90,
    // Safari handled separately below — do not add here.
  };

  final browserName = browser.name;
  final browserVersion = browser.version;
  final userAgent = html.window.navigator.userAgent;

  // All iOS browsers use WebKit (Apple policy), so they all share the same
  // WebRTC limitations with Agora (peerConnection drops, subscribe failures).
  final isMobileApple = RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent);
  if (isMobileApple) {
    return const BrowserCompatibilityResult(
      isCompatible: false,
      message:
          'Mobile browsers on iOS have limited support for audio/video. '
          'If you experience any audio/visual issues, please re-join from a desktop browser like Chrome or Firefox.',
    );
  }

  // Safari: minimum 16.4 (canvas.captureStream added in Safari 16.4, March 2023).
  if (browserName == 'Safari') {
    final major = browserVersion.major;
    final minor = browserVersion.minor;
    final meetsMin = major > 16 || (major == 16 && minor >= 4);
    if (!meetsMin) {
      return BrowserCompatibilityResult(
        isCompatible: false,
        message:
            'Safari ${browserVersion.major}.${browserVersion.minor} is not supported. '
            'Please update to Safari 16.4 or later, or use Chrome or Firefox.',
      );
    }
    return const BrowserCompatibilityResult(isCompatible: true);
  }

  // Check Chrome, Firefox, and other known browsers via platform_detect.
  if (minMajorVersions.containsKey(browserName)) {
    if (browserVersion.major < minMajorVersions[browserName]!) {
      return BrowserCompatibilityResult(
        isCompatible: false,
        message: warningMessage,
      );
    }
    return const BrowserCompatibilityResult(isCompatible: true);
  }

  // Fall back to user agent parsing for Edge and other browsers
  // Edge reports as "Edg/" in user agent
  final edgeMatch = RegExp(r'Edg/(\d+)').firstMatch(userAgent);
  if (edgeMatch != null) {
    final majorVersion = int.tryParse(edgeMatch.group(1)!) ?? 0;
    if (majorVersion < 90) {
      return BrowserCompatibilityResult(
        isCompatible: false,
        message: warningMessage,
      );
    }
    return const BrowserCompatibilityResult(isCompatible: true);
  }

  // Unknown browser — show warning
  if (browserName == 'Unknown') {
    return BrowserCompatibilityResult(
      isCompatible: false,
      message: warningMessage,
    );
  }

  return const BrowserCompatibilityResult(isCompatible: true);
}
