import 'dart:js_util' as js_util;
import 'package:universal_html/html.dart' as html;

/// Service for dynamically updating Open Graph and Twitter Card meta tags
/// This enables proper social media sharing with context-appropriate images and descriptions
class MetaTagService {
  /// Strips HTML tags from a string to make it safe for meta tag content
  /// Meta tags should only contain plain text, not HTML markup
  static String _stripHtmlTags(String text) {
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

  /// Converts HTTP URLs to HTTPS for security and platform requirements
  static String _ensureHttps(String url) {
    if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'https://');
    }
    return url;
  }
  static const String defaultTitle = 'AllSides Roundtables';
  static const String defaultDescription = 'Enabling constructive dialogue.';
  static const String defaultImageUrl =
      'https://roundtables.allsides.com/allsides-logo-open-graph.png';
  static const String defaultUrl = 'https://roundtables.allsides.com/';

  /// Updates all social media meta tags (Open Graph and Twitter Card)
  static void updateMetaTags({
    required String title,
    required String description,
    required String imageUrl,
    required String url,
    int? imageWidth,
    int? imageHeight,
  }) {
    // Update page title
    html.document.title = title;

    // Update Open Graph tags
    _updateMetaTag('og:title', title);
    _updateMetaTag('og:description', description);
    _updateMetaTag('og:image', imageUrl);
    _updateMetaTag('og:url', url);

    if (imageWidth != null) {
      _updateMetaTag('og:image:width', imageWidth.toString());
    }
    if (imageHeight != null) {
      _updateMetaTag('og:image:height', imageHeight.toString());
    }

    // Update Twitter Card tags
    _updateMetaTag('twitter:title', title, isProperty: false);
    _updateMetaTag('twitter:description', description, isProperty: false);
    _updateMetaTag('twitter:image', imageUrl, isProperty: false);

    // Update standard meta description
    _updateMetaTag('description', description, isProperty: false, isName: true);
  }

  /// Updates community-specific meta tags
  static void updateCommunityMetaTags({
    required String communityName,
    String? communityDescription,
    String? communityImageUrl,
    required String communityUrl,
  }) {
    final title = '$communityName | $defaultTitle';
    final description = communityDescription ?? defaultDescription;
    final imageUrl = communityImageUrl ?? defaultImageUrl;

    updateMetaTags(
      title: title,
      description: description,
      imageUrl: imageUrl,
      url: communityUrl,
    );
  }

  /// Updates event-specific meta tags
  static void updateEventMetaTags({
    required String eventTitle,
    String? eventDescription,
    String? eventImageUrl,
    required String eventUrl,
    required String communityName,
  }) {
    final title = '$eventTitle | $communityName | $defaultTitle';
    final description = eventDescription ?? defaultDescription;
    final imageUrl = eventImageUrl ?? defaultImageUrl;

    updateMetaTags(
      title: title,
      description: description,
      imageUrl: imageUrl,
      url: eventUrl,
    );
  }

  /// Resets meta tags to default values (for home page)
  static void resetToDefaults() {
    updateMetaTags(
      title: defaultTitle,
      description: defaultDescription,
      imageUrl: defaultImageUrl,
      url: defaultUrl,
    );
  }

  /// Helper method to update or create a meta tag
  static void _updateMetaTag(
    String property,
    String content, {
    bool isProperty = true,
    bool isName = false,
  }) {
    final attributeName = isName ? 'name' : (isProperty ? 'property' : 'name');
    
    // Sanitize content based on property type
    var sanitizedContent = content;
    
    // Strip HTML tags from description fields
    if (property.toLowerCase().contains('description')) {
      sanitizedContent = _stripHtmlTags(sanitizedContent);
    }
    
    // Convert HTTP to HTTPS for image fields
    if (property.toLowerCase().contains('image')) {
      sanitizedContent = _ensureHttps(sanitizedContent);
    }
    
    // Find existing meta tag
    html.MetaElement? metaTag = html.document.querySelector(
      'meta[$attributeName="$property"]',
    ) as html.MetaElement?;

    if (metaTag != null) {
      // Update existing tag
      metaTag.content = sanitizedContent;
    } else {
      // Create new meta tag if it doesn't exist
      metaTag = html.MetaElement();
      if (isProperty) {
        js_util.setProperty(metaTag, 'property', property);
      } else {
        metaTag.name = property;
      }
      metaTag.content = sanitizedContent;
      html.document.head?.append(metaTag);
    }
  }
}

