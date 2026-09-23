/// Hark's `volume_change` event passes a JS number. dartify maps integer-valued
/// JS numbers to [int], which is not a subtype of [double] on dart2js.
double? harkVolumeToDouble(Object? volume) {
  if (volume is num) return volume.toDouble();
  return null;
}
