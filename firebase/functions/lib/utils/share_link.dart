import 'dart:async';
import 'dart:convert';

import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import 'package:intl/intl.dart';
import '../cloud_function.dart';
import 'infra/firestore_utils.dart';
import 'timezone_utils.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/community/community.dart';
import 'package:timezone/standalone.dart' as tz;
import 'template_utils.dart';

class ShareLink implements CloudFunction {
  @override
  final String functionName = 'ShareLink';

  String get _appName => functions.config.get('app.name') as String? ?? 'AllSides Roundtables';

  /// Strips HTML tags from a string to make it safe for meta tag content
  /// Meta tags should only contain plain text, not HTML markup
  String _stripHtmlTags(String text) {
    // Remove HTML tags using regex
    final stripped = text.replaceAll(RegExp(r'<[^>]*>'), '');
    // Decode common HTML entities
    return stripped
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&'); // This should be last to avoid double-decoding
  }

  /// Remove /share/
  String _getRedirect(String requestedUri) {
    print('Getting redirect');
    if (requestedUri.contains('/share/community/')) {
      return requestedUri.replaceFirst("/share/community/", "/space/");
    } else if (requestedUri.contains('/share/')) {
      print('Replacing share');
      return requestedUri.replaceFirst("/share/", "/");
    } else {
      return requestedUri;
    }
  }

  String _getAppPath(Uri requestedUri) {
    return requestedUri.pathSegments.skip(1).join('/');
  }

  Future<String> _getHtmlContent(
    String requestedUri, {
    bool isLinkedIn = false,
  }) async {
    final redirect = _getRedirect(requestedUri);
    final appPath = _getAppPath(Uri.parse(requestedUri));

    var title = '$_appName - Real Deliberations, Meaningful Communities';
    var image = functions.config.get('app.banner_image_url') as String? ?? '';
    var description =
        'Deliberations with real people in real time, for any interest.';

    final eventMatch =
        RegExp('(?:space|community)/([^/]+)/discuss/([^/]+)/([^/]+)')
            .matchAsPrefix(appPath);
    final communityMatch =
        RegExp('(?:space|community)/([^/]+)').matchAsPrefix(appPath);
    if (eventMatch != null) {
      var communityId = eventMatch.group(1);
      final templateId = eventMatch.group(2);
      final eventId = eventMatch.group(3);

      try {
        final communityDoc =
            await firestore.document('community/$communityId').get();
        final community = Community.fromJson(
          firestoreUtils.fromFirestoreJson(communityDoc.data.toMap()),
        );

      final templateDoc = await firestore
          .document('community/$communityId/templates/$templateId')
          .get();
      final template = TemplateUtils.templateFromSnapshot(templateDoc);

      final eventDoc = await firestore
          .document(
            'community/$communityId/templates/$templateId/events/$eventId',
          )
          .get();
      final event = Event.fromJson(
        firestoreUtils.fromFirestoreJson(eventDoc.data.toMap()),
      );

      final scheduledTimeUtc = event.scheduledTime?.toUtc();

      tz.Location scheduledLocation;
      try {
        scheduledLocation =
            timezoneUtils.getLocation(event.scheduledTimeZone ?? '');
      } catch (e) {
        print(
          'Error getting scheduled location: $e. Using America/Los_Angeles',
        );
        scheduledLocation = timezoneUtils.getLocation('America/Los_Angeles');
      }
      final timeZoneAbbreviation = scheduledLocation.currentTimeZone.abbr;

      tz.TZDateTime scheduledTimeLocal =
          tz.TZDateTime.from(scheduledTimeUtc!, scheduledLocation);

      final date = DateFormat('E, MMM d').format(scheduledTimeLocal);
      final time = DateFormat('h:mm a').format(scheduledTimeLocal);

      title = 'Join my event on ${event.title ?? template.title}!';
      description = '$_appName - $date $time $timeZoneAbbreviation - Join '
          '${community.name} on $_appName!';
      image = event.image ?? template.image ?? community.bannerImageUrl ?? '';
      } catch (e) {
        print('Error loading community/event data for share link: $e');
        // Use default values if we can't load the event details
        title = '$_appName - Join us for a discussion!';
        description = 'Real Deliberations, Meaningful Communities';
        // image already has fallback value from line 60
      }
    } else if (communityMatch != null) {
      var communityId = communityMatch.group(1);

      try {
        final communityDoc =
            await firestore.document('community/$communityId').get();
        final community = Community.fromJson(
          firestoreUtils.fromFirestoreJson(communityDoc.data.toMap()),
        );

        title = '${community.name} on $_appName';
        description = community.description ?? description;
        image = community.bannerImageUrl ?? '';
      } catch (e) {
        print('Error loading community data for share link: $e');
        // Use default values if we can't load the community details
        title = '$_appName - Join the conversation!';
        // description and image already have fallback values
      }
    }

    if (isLinkedIn &&
        image.contains('picsum.photos') &&
        image.contains('.webp')) {
      image = image.replaceAll('.webp', '');
    }

    print(image);
    
    // Ensure we have a valid image URL (LinkedIn requires this)
    if (image.isEmpty) {
      image = functions.config.get('app.banner_image_url') as String? ?? '';
    }
    
    // Convert HTTP to HTTPS for security and platform requirements
    if (image.startsWith('http://')) {
      image = image.replaceFirst('http://', 'https://');
    }
    
    // Sanitize description by stripping HTML tags for meta tag content
    final sanitizedDescription = _stripHtmlTags(description);
    
    // HTML-escape all dynamic content to prevent malformed HTML
    const htmlEscape = HtmlEscape();
    final titleEscaped = htmlEscape.convert(title);
    final descriptionEscaped = htmlEscape.convert(sanitizedDescription);
    final urlEscaped = htmlEscape.convert(requestedUri);
    final imageEscaped = htmlEscape.convert(image);
    final redirectEscaped = htmlEscape.convert(redirect);
    
    return '''
      <html>
      <head>
        <meta charset="UTF-8">
        <meta content="IE=Edge" http-equiv="X-UA-Compatible">
        <meta name="description" content="$descriptionEscaped">

        <meta property="og:type" content="website"/>
        <meta property="og:title" content="$titleEscaped"/>
        <meta property="og:description" content="$descriptionEscaped"/>
        <meta property="og:url" content="$urlEscaped"/>
        <meta property="og:image" content="$imageEscaped"/>
        <meta name="image" property="og:image" content="$imageEscaped">

        <meta name="twitter:title" content="$titleEscaped">
        <meta name="twitter:description" content="$descriptionEscaped">
        <meta name="twitter:image" content="$imageEscaped">
        <meta name="twitter:card" content="summary_large_image">

        <title>$titleEscaped</title>

      </head>
      <body>
        <p><a href="$redirectEscaped">Click here</a> to continue!</p>
      </body>
      </html>
    ''';
  }

  Future<void> expressAction(ExpressHttpRequest expressRequest) async {
    try {
      // Determine what resource is being requested from URL
      print(expressRequest.requestedUri.toString());

      // Necessary because the expressRequest requested URI object is not actually a dart URI
      final requestedUri = Uri.parse(expressRequest.requestedUri.toString());
      print(requestedUri.toString());

      final userAgent =
          expressRequest.headers.value('User-Agent')?.toLowerCase() ?? '';
      if (userAgent.contains('facebookexternalhit') ||
          userAgent.contains('facebot') ||
          userAgent.contains('twitterbot') ||
          userAgent.contains('linkedinbot')) {
        expressRequest.response.headers.add("Cache-Control", "no-cache");
        expressRequest.response.write(
          await _getHtmlContent(
            expressRequest.requestedUri.toString(),
            isLinkedIn: userAgent.contains('linkedinbot'),
          ),
        );
      } else {
        return await expressRequest.response.redirect(
          Uri.parse(_getRedirect(expressRequest.requestedUri.toString())),
        );
      }
    } catch (e, stacktrace) {
      print('Error during action');
      print(e);
      print(stacktrace);
      expressRequest.response.addError(e, stacktrace);
    }

    await expressRequest.response.close();
  }

  @override
  void register(FirebaseFunctions functions) {
    functions[functionName] = functions
        .runWith(
          RuntimeOptions(timeoutSeconds: 60, memory: '1GB', minInstances: 0),
        )
        .https
        .onRequest(expressAction);
  }
}
