/// Whether a Matomo call should go out now, wait for initialize, or be skipped
/// because tracking is off or init already failed.
enum MatomoSendDecision {
  sendNow,
  waitForInit,
  skip,
}

MatomoSendDecision matomoSendDecision({
  required bool trackingEnabled,
  required bool trackerInitialized,
  required bool initFailed,
}) {
  if (!trackingEnabled || initFailed) return MatomoSendDecision.skip;
  if (!trackerInitialized) return MatomoSendDecision.waitForInit;
  return MatomoSendDecision.sendNow;
}
