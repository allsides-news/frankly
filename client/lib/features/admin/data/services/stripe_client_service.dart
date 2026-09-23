import 'package:universal_html/html.dart' as html;

import 'package:client/features/admin/data/services/stripe_checkout_redirect_stub.dart'
    if (dart.library.html) 'package:client/features/admin/data/services/stripe_checkout_redirect_web.dart';

class StripeClientService {
  /// Opens Stripe Checkout in the browser (web only).
  ///
  /// Throws [UnsupportedError] on non-web targets, and on web throws
  /// [StateError] if `window.stripe` is missing (Stripe.js not loaded), if
  /// `redirectToCheckout` resolves with a Stripe error payload (`error` key),
  /// or if the underlying Promise rejects.
  Future<void> redirectToCheckout({required String sessionId}) {
    return redirectStripeToCheckout(html.window, sessionId);
  }
}
