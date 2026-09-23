/// Non-web analysis target: Cloudinary desktop picker is not supported here.
void callWindowPickMedia(
  Object window,
  Map<String, Object?> parameters,
  void Function(Object? error, Object? result) callback,
) {
  throw UnsupportedError('Cloudinary media picker is only supported on web');
}
