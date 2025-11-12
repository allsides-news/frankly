import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:client/config/environment.dart';

/// A widget that renders HTML content safely
/// Falls back to plain text if HTML parsing fails
class HtmlContent extends StatelessWidget {
  final String content;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const HtmlContent(
    this.content, {
    Key? key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  }) : super(key: key);

  String _prepareContent(String text) {
    // Always convert plain text newlines to HTML breaks
    // This ensures line breaks are preserved whether or not HTML tags are present
    String prepared = text.replaceAll('\n', '<br>');

    // Wrap in a div to ensure proper HTML structure for rendering
    // The flutter_html package works better with properly structured HTML
    return '<div>$prepared</div>';
  }

  /// Proxy external URLs through the imageProxy cloud function to avoid CORS issues
  String _proxyUrl(String url) {
    // Only proxy external URLs when running on web
    if (!kIsWeb) {
      return url;
    }

    // Proxy all external HTTP/HTTPS URLs to avoid CORS issues
    final isExternalUrl = url.startsWith('http://') || url.startsWith('https://');
    
    if (isExternalUrl) {
      return '${Environment.functionsUrlPrefix}/imageProxy?url=${Uri.encodeQueryComponent(url)}';
    }

    return url;
  }

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }

    // Prepare content (convert newlines to <br> if needed)
    final preparedContent = _prepareContent(content);

    // Always render as HTML to preserve formatting
    return Html(
      data: preparedContent,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: style?.fontSize != null 
              ? FontSize(style!.fontSize!) 
              : null,
          color: style?.color,
          fontFamily: style?.fontFamily,
          fontWeight: style?.fontWeight,
          textAlign: _convertTextAlign(textAlign),
          whiteSpace: WhiteSpace.normal,
        ),
        'div': Style(
          display: Display.block,
        ),
        'br': Style(
          display: Display.block,
        ),
        'p': Style(
          margin: Margins.only(bottom: 8),
        ),
        'h1': Style(
          fontSize: FontSize(24),
          fontWeight: FontWeight.bold,
          margin: Margins.only(top: 8, bottom: 8),
        ),
        'h2': Style(
          fontSize: FontSize(20),
          fontWeight: FontWeight.bold,
          margin: Margins.only(top: 8, bottom: 8),
        ),
        'h3': Style(
          fontSize: FontSize(18),
          fontWeight: FontWeight.bold,
          margin: Margins.only(top: 8, bottom: 8),
        ),
        'ul': Style(
          margin: Margins.only(left: 16, bottom: 8),
        ),
        'ol': Style(
          margin: Margins.only(left: 16, bottom: 8),
        ),
        'li': Style(
          margin: Margins.only(bottom: 4),
        ),
        'a': Style(
          color: Colors.blue,
          textDecoration: TextDecoration.underline,
        ),
        'img': Style(
          width: Width.auto(),
          maxLines: null,
        ),
      },
      extensions: [
        TagExtension(
          tagsToExtend: {'img'},
          builder: (extensionContext) {
            final src = extensionContext.attributes['src'];
            final alt = extensionContext.attributes['alt'] ?? 'Image';
            
            if (src == null || src.isEmpty) {
              return const SizedBox.shrink();
            }

            // Proxy external URLs to avoid CORS issues
            final proxiedSrc = _proxyUrl(src);

            // Check if it's an SVG
            if (src.toLowerCase().endsWith('.svg')) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: SvgPicture.network(
                  proxiedSrc,
                  width: 300,
                  placeholderBuilder: (context) => const CircularProgressIndicator(),
                  fit: BoxFit.contain,
                ),
              );
            }

            // For other image types (PNG, JPG, GIF, WebP, etc.)
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Image.network(
                proxiedSrc,
                width: 300,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator();
                },
                errorBuilder: (context, error, stackTrace) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image, size: 50),
                      Text('Failed to load: $alt', style: const TextStyle(fontSize: 12)),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ],
      onLinkTap: (url, attributes, element) {
        if (url != null) {
          _launchUrl(url);
        }
      },
    );
  }

  TextAlign? _convertTextAlign(TextAlign? align) {
    if (align == null) return null;
    switch (align) {
      case TextAlign.left:
        return TextAlign.left;
      case TextAlign.right:
        return TextAlign.right;
      case TextAlign.center:
        return TextAlign.center;
      case TextAlign.justify:
        return TextAlign.justify;
      default:
        return null;
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }
}

