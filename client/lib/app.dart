import 'dart:async';

import 'package:beamer/beamer.dart';
import 'package:client/styles/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart' hide Router;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/config/environment.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/services.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:client/core/localization/locale_provider.dart';
// Generated localization classes
import 'l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sentry/sentry.dart';
import 'package:uuid/uuid.dart';

import 'firebase_options.dart';

bool kShowStripeFeatures = false;

/// Master switch for the Posts/discussion-threads nav entries (nav bar link,
/// chat bubble icon, sidebar link). Independent of each Space's own
/// [CommunitySettings.enableDiscussionThreads] value, which stays intact
/// underneath this so it's a one-line revert once this should show again.
bool kShowDiscussionThreadsNav = false;

bool useBotControls = false;
Map<String, String>? botJoinParameters;

// If a SENTRY_RELEASE is supplied via `--dart-define=SENTRY_RELEASE=whatever` on build, then
// we do Sentry reporting
const String sentryRelease =
    String.fromEnvironment('SENTRY_RELEASE', defaultValue: '');
bool enableSentry = sentryRelease != '';

final uuid = Uuid();

Future<void> reportError(dynamic error, dynamic stackTrace) async {
  loggingService.log(
    'reportError: error',
    logType: LogType.error,
    error: error,
    stackTrace: stackTrace,
  );

  if (enableSentry) {
    // Send the Exception and Stacktrace to the indicated Sentry dsn
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> runClient({FirebaseOptions? firebaseOptions}) async {
  setURLPathStrategy();

  await Firebase.initializeApp(
    options: firebaseOptions ?? DefaultFirebaseOptions.currentPlatform,
  );

  if (enableSentry) {
    await Sentry.init(
      (options) => options
        ..dsn = Environment.sentryDSN
        ..environment = Environment.sentryEnvironment
        ..beforeSend = (event, hint) {
          // Drop errors injected by third-party browser scripts (e.g. Facebook
          // in-app browser's inject_content.js). These are not actionable.
          final frames = event.exceptions
                  ?.expand((e) => e.stackTrace?.frames ?? [])
                  .toList() ??
              [];
          // Only suppress the specific Facebook in-app browser injection script,
          // not any path that contains "facebook" (which could include FB SDK files
          // that are intentionally loaded by the app).
          final isThirdPartyInjection = frames.any(
            (f) => f.absPath?.contains('inject_content.js') == true,
          );
          if (isThirdPartyInjection) return null;

          // Expected when security rules deny a private event (signed-out or
          // before RSVP). CustomStreamBuilder already renders an error UI.
          final exceptionValue =
              event.exceptions?.map((e) => e.value ?? '').join(' ') ?? '';
          if (exceptionValue.contains('permission-denied')) {
            return null;
          }
          if (isTransientAuthNetworkError(exceptionValue)) {
            return null;
          }
          return event;
        },
    );
  }

  FlutterError.onError = (details) {
    reportError(details.exception, details.stack);
  };

  runZonedGuarded(
    () => runApp(App()),
    (error, stackTrace) {
      reportError(error, stackTrace);
    },
  );
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  final _localeProvider = LocaleProvider();

  @override
  void initState() {
    super.initState();

    initializeTimezones();
    _localeProvider.init();
    createServices();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: userService),
        ChangeNotifierProvider.value(value: userDataService),
        ChangeNotifierProvider.value(value: dialogProvider),
        Provider.value(value: firestoreDatabase),
        ChangeNotifierProvider(create: (_) => NavBarProvider()),
        ChangeNotifierProvider.value(value: _localeProvider),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return Portal(
            child: MaterialApp.router(
              locale: localeProvider.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('en'),
                Locale('es'),
                Locale.fromSubtags(
                  languageCode: 'zh',
                  scriptCode: 'Hant',
                  countryCode: 'TW',
                ),
                Locale('zh'),
              ],
              shortcuts: {
                ...WidgetsApp.defaultShortcuts,
                LogicalKeySet(LogicalKeyboardKey.space): ActivateIntent(),
                LogicalKeySet(LogicalKeyboardKey.shift): DoNothingIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowUp): DoNothingIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowDown): DoNothingIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowLeft): DoNothingIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowRight): DoNothingIntent(),
              },
              routerDelegate: routerDelegate,
              backButtonDispatcher:
                  BeamerBackButtonDispatcher(delegate: routerDelegate),
              routeInformationParser: BeamerParser(),
              theme: appTheme,
              darkTheme: appDarkTheme,
              themeMode: ThemeMode.system,
            ),
          );
        },
      ),
    );
  }
}
