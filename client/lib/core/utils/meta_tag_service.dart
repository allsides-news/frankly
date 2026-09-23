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

  /// Transforms a Cloudinary image URL to OG-optimal dimensions (1200×630).
  ///
  /// Inserts `w_1200,h_630,c_fill,q_auto,f_jpg` after `/upload/` so Cloudinary
  /// returns a properly-sized image instead of the raw uploaded asset.
  /// Returns the original URL unchanged for non-Cloudinary URLs or URLs that
  /// already carry any transform parameters (detected by the `[a-z]_` prefix
  /// pattern common to all Cloudinary transform segments).
  static String _toOgImageUrl(String url) {
    const uploadSegment = '/upload/';
    if (!url.contains('res.cloudinary.com') || !url.contains(uploadSegment)) {
      return url;
    }
    const transform = 'w_1200,h_630,c_fill,q_auto,f_jpg';
    final idx = url.indexOf(uploadSegment) + uploadSegment.length;
    final remainder = url.substring(idx);
    // Any Cloudinary transform segment starts with a single lowercase letter
    // followed by an underscore (e.g. w_, h_, c_, f_, q_, b_, r_, e_, l_…).
    // NOTE: Public IDs that happen to start with a single letter + underscore
    // (e.g. `a_photo.jpg`, `e_event_banner.jpg`) will also match this heuristic
    // and bypass the transform. This is an accepted trade-off; rename such
    // assets if OG transforms need to be applied to them.
    if (RegExp(r'^[a-z]_').hasMatch(remainder)) {
      return url;
    }
    return '${url.substring(0, idx)}$transform/${url.substring(idx)}';
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
    } else {
      _removeMetaTag('og:image:width');
    }
    if (imageHeight != null) {
      _updateMetaTag('og:image:height', imageHeight.toString());
    } else {
      _removeMetaTag('og:image:height');
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
    final rawImageUrl = communityImageUrl ?? defaultImageUrl;
    final imageUrl = _toOgImageUrl(rawImageUrl);
    final wasTransformed = imageUrl != rawImageUrl;

    updateMetaTags(
      title: title,
      description: description,
      imageUrl: imageUrl,
      url: communityUrl,
      imageWidth: wasTransformed ? 1200 : null,
      imageHeight: wasTransformed ? 630 : null,
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
    final rawImageUrl = eventImageUrl ?? defaultImageUrl;
    final imageUrl = _toOgImageUrl(rawImageUrl);
    final wasTransformed = imageUrl != rawImageUrl;

    updateMetaTags(
      title: title,
      description: description,
      imageUrl: imageUrl,
      url: eventUrl,
      imageWidth: wasTransformed ? 1200 : null,
      imageHeight: wasTransformed ? 630 : null,
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

  /// Removes a meta tag from the DOM by property name, if it exists.
  /// Used to clear dimension tags when navigating to a page where dimensions
  /// are unknown, preventing stale values from a prior page being reported.
  static void _removeMetaTag(String property) {
    final tag = html.document.querySelector(
      'meta[property="$property"]',
    ) as html.MetaElement?;
    tag?.remove();
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
        metaTag.setAttribute('property', property);
      } else {
        metaTag.name = property;
      }
      metaTag.content = sanitizedContent;
      html.document.head?.append(metaTag);
    }
  }
}

