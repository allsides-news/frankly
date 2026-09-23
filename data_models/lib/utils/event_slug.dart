String eventTitleToSlug(String? title) {
  final normalized = title
      ?.trim()
      .toLowerCase()
      .replaceAll(RegExp(r"['\u2018\u2019]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  if (normalized == null || normalized.isEmpty) {
    return 'event';
  }

  return normalized;
}
