/// Non-web target: Stripe.js checkout redirect is not available.
Future<void> redirectStripeToCheckout(Object window, String sessionId) {
  return Future.error(
    UnsupportedError('Stripe checkout redirect is only supported on web'),
  );
}
