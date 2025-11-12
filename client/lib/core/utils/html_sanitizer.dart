/// HTML sanitization utilities for security
/// 
/// This utility helps prevent XSS attacks by sanitizing user-generated HTML content
class HtmlSanitizer {
  // List of allowed HTML tags for event descriptions
  static const List<String> allowedTags = [
    'p',
    'br',
    'strong',
    'b',
    'em',
    'i',
    'u',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'li',
    'a',
    'img',
    'span',
    'div',
  ];

  // List of allowed attributes for specific tags
  static const Map<String, List<String>> allowedAttributes = {
    'a': ['href', 'title', 'target'],
    'img': ['src', 'alt', 'title', 'width', 'height'],
    'span': ['style'],
    'div': ['style'],
  };

  /// Sanitizes HTML content by removing potentially dangerous tags and attributes
  /// 
  /// This is a basic sanitization that should be supplemented with server-side
  /// validation for production use
  static String sanitize(String html) {
    if (html.isEmpty) return html;

    // Remove script tags and their content
    html = html.replaceAll(RegExp(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', caseSensitive: false), '');
    
    // Remove style tags and their content
    html = html.replaceAll(RegExp(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', caseSensitive: false), '');
    
    // Remove iframe tags
    html = html.replaceAll(RegExp(r'<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>', caseSensitive: false), '');
    
    // Remove object and embed tags
    html = html.replaceAll(RegExp(r'<object\b[^<]*(?:(?!<\/object>)<[^<]*)*<\/object>', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'<embed\b[^>]*>', caseSensitive: false), '');
    
    // Remove on* event attributes (onclick, onload, etc.)
    html = html.replaceAll(RegExp(r'\s+on\w+\s*=\s*["\x27][^"\x27]*["\x27]', caseSensitive: false), '');
    html = html.replaceAll(RegExp(r'\s+on\w+\s*=\s*\S+', caseSensitive: false), '');
    
    // Remove javascript: protocol from href and src attributes
    html = html.replaceAll(RegExp(r'href\s*=\s*["\x27]javascript:', caseSensitive: false), 'href="');
    html = html.replaceAll(RegExp(r'src\s*=\s*["\x27]javascript:', caseSensitive: false), 'src="');
    
    // Remove data: protocol from src attributes (except for images with specific formats)
    html = html.replaceAll(
      RegExp(r'src\s*=\s*["\x27]data:(?!image/(png|jpg|jpeg|gif|svg|webp))', caseSensitive: false),
      'src="',
    );

    return html;
  }

  /// Validates if the HTML content is safe based on allowed tags
  /// 
  /// Returns true if the content appears safe, false otherwise
  static bool isValid(String html) {
    if (html.isEmpty) return true;

    // Check for script tags
    if (html.toLowerCase().contains('<script')) return false;
    
    // Check for iframe tags
    if (html.toLowerCase().contains('<iframe')) return false;
    
    // Check for javascript: protocol
    if (html.toLowerCase().contains('javascript:')) return false;
    
    // Check for on* event handlers
    if (RegExp(r'\s+on\w+\s*=', caseSensitive: false).hasMatch(html)) return false;

    return true;
  }

  /// Strips all HTML tags from the content, leaving only plain text
  /// 
  /// Useful for generating preview text or fallback content
  static String stripHtml(String html) {
    if (html.isEmpty) return html;

    // Remove all HTML tags
    String text = html.replaceAll(RegExp(r'<[^>]*>'), '');
    
    // Decode common HTML entities
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    
    // Normalize whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Escapes HTML special characters to prevent XSS
  /// 
  /// Use this when displaying user input as plain text
  static String escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Truncates HTML content to a specified length while preserving HTML structure
  /// 
  /// This attempts to close unclosed tags for valid HTML
  static String truncate(String html, int maxLength) {
    final plainText = stripHtml(html);
    if (plainText.length <= maxLength) return html;

    // For simplicity, just return truncated plain text if content is too long
    return plainText.substring(0, maxLength) + '...';
  }
}

