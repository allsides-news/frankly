import 'dart:async';

import 'package:client/config/environment.dart';
import 'package:client/core/data/services/matomo_send_decision.dart';
import 'package:client/services.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/utils/event_slug.dart';
import 'package:flutter/foundation.dart';
import 'package:matomo_tracker/matomo_tracker.dart';

export 'package:client/core/data/services/matomo_send_decision.dart';

class AnalyticsService {
  bool enableMatomo = Environment.matomoURL != '';

  Future<void>? _initFuture;
  bool _initFailed = false;

  Future<void> initialize() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    debugPrint(
      '[Matomo] enableMatomo=$enableMatomo  url="${Environment.matomoURL}"  siteId="${Environment.matomoSiteId}"',
    );
    if (!enableMatomo || MatomoTracker.instance.initialized) {
      return;
    }
    try {
      final url = Environment.matomoURL.endsWith('matomo.php')
          ? Environment.matomoURL
          : '${Environment.matomoURL.replaceAll(RegExp(r'/$'), '')}/matomo.php';
      debugPrint('[Matomo] resolved tracking URL: $url');
      await MatomoTracker.instance.initialize(
        siteId: Environment.matomoSiteId,
        url: url,
        cookieless: true,
        dispatchSettings: const DispatchSettings.persistent(),
      );
      debugPrint('[Matomo] initialized successfully');
    } catch (e, st) {
      // Ad blockers and a blocked matomo.php URL fail here. Disable so later
      // logPageView/logEvent do not throw UninitializedMatomoInstanceException.
      enableMatomo = false;
      _initFailed = true;
      debugPrint('[Matomo] initialization error: $e\n$st');
      return;
    }

    // app_start is tracking, not init. Keep it off the init future so a
    // throw cannot set _initFailed or drop events waiting on initialize().
    unawaited(
      Future.sync(() {
        MatomoTracker.instance.trackPageViewWithName(actionName: 'app_start');
        debugPrint('[Matomo] trackPageView sent: app_start');
      }),
    );
  }

  /// Track a screen/page view.
  /// Pass [communityId] and/or [eventId] to preserve navigation context as
  /// Matomo custom dimensions so filters like "how many people from Space X
  /// later entered a meeting" are possible in the dashboard.
  void logPageView(
    String screenName, {
    String? communityId,
    String? eventId,
  }) {
    _sendOrWait(() {
      final dimensions = {
        if (communityId != null) 'dimension1': communityId,
        if (eventId != null) 'dimension2': eventId,
        if (userService.currentUserId != null)
          'dimension3': userService.currentUserId!,
      };

      debugPrint(
        '[Matomo] trackPageView screen=$screenName communityId=$communityId eventId=$eventId',
      );
      MatomoTracker.instance.trackPageViewWithName(
        actionName: screenName,
        dimensions: dimensions,
      );
    });
  }

  /// Call to track a user event
  void logEvent(
    AnalyticsEvent event, {
    String? eventTitle,
    String? communityName,
  }) {
    if (!enableMatomo) {
      debugPrint('[Matomo] skipped (disabled): ${event.getEventType()}');
      return;
    }

    _sendOrWait(() {
      final eventProps = event.toJson();
      final communityId = eventProps['communityId'];
      final eventName = eventTitle != null && eventTitle.trim().isNotEmpty
          ? eventTitleToSlug(eventTitle)
          : communityName != null && communityName.trim().isNotEmpty
              ? eventTitleToSlug(communityName)
              : event.getEventName();

      final dimensions = {
        if (communityId != null) 'dimension1': communityId.toString(),
        if (userService.currentUserId != null)
          'dimension3': userService.currentUserId!,
      };

      debugPrint(
        '[Matomo] trackEvent category=${event.getEventCategory()} action=${event.getEventType()} name=$eventName',
      );
      MatomoTracker.instance.trackEvent(
        eventInfo: EventInfo(
          category: event.getEventCategory(),
          action: event.getEventType(),
          name: eventName,
          value: event.getMetricValue(),
        ),
        dimensions: dimensions,
      );
    });
  }

  void _sendOrWait(void Function() send) {
    switch (matomoSendDecision(
      trackingEnabled: enableMatomo,
      trackerInitialized: MatomoTracker.instance.initialized,
      initFailed: _initFailed,
    )) {
      case MatomoSendDecision.skip:
        return;
      case MatomoSendDecision.sendNow:
        send();
        return;
      case MatomoSendDecision.waitForInit:
        unawaited(_sendAfterInit(send));
    }
  }

  Future<void> _sendAfterInit(void Function() send) async {
    await initialize();
    if (matomoSendDecision(
          trackingEnabled: enableMatomo,
          trackerInitialized: MatomoTracker.instance.initialized,
          initFailed: _initFailed,
        ) !=
        MatomoSendDecision.sendNow) {
      return;
    }
    send();
  }
}
