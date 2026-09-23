import 'package:client/features/events/features/live_meeting/features/video/data/providers/audio_level_volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('harkVolumeToDouble', () {
    test('promotes JS integer-valued numbers to double', () {
      expect(harkVolumeToDouble(42), 42.0);
      expect(harkVolumeToDouble(42), isA<double>());
    });

    test('passes through doubles', () {
      expect(harkVolumeToDouble(-51.3), -51.3);
    });

    test('returns null for missing or non-numeric values', () {
      expect(harkVolumeToDouble(null), isNull);
      expect(harkVolumeToDouble('loud'), isNull);
    });
  });
}
