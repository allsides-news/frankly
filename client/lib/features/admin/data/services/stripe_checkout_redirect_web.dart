import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<void> redirectStripeToCheckout(Object window, String sessionId) async {
  final win = window as JSObject;
  final stripeObj = win['stripe'];
  if (stripeObj == null) {
    throw StateError(
      'redirectStripeToCheckout: window.stripe is not defined — '
      'ensure Stripe.js is loaded before calling redirectToCheckout.',
    );
  }
  final result = (stripeObj as JSObject).callMethodVarArgs(
    'redirectToCheckout'.toJS,
    [(<String, Object?>{'sessionId': sessionId}).jsify()],
  );
  // Stripe resolves (not rejects) with { error } on failure; successful redirect
  // navigates away so the awaited future often does not complete here.
  if (result == null) return;
  final resolved = await (result as JSPromise<JSAny?>).toDart;
  final payload = resolved?.dartify();
  if (payload is Map && payload['error'] != null) {
    throw StateError('Stripe redirectToCheckout error: $payload');
  }
}
