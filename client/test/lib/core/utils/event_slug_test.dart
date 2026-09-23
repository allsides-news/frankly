import 'package:data_models/utils/event_slug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('eventTitleToSlug', () {
    test('converts an event title to a lowercase hyphenated slug', () {
      expect(
        eventTitleToSlug("Is America Losing its Independent Media?"),
        'is-america-losing-its-independent-media',
      );
    });

    test('removes punctuation and collapses whitespace', () {
      expect(
        eventTitleToSlug('  Town Hall: Left & Right!  '),
        'town-hall-left-right',
      );
    });

    test('removes apostrophes without splitting words', () {
      expect(
        eventTitleToSlug("What’s Next for America?"),
        'whats-next-for-america',
      );
    });

    test('removes left and right smart quotation marks', () {
      expect(
        eventTitleToSlug('‘What’s Next’'),
        'whats-next',
      );
    });

    test('returns a fallback for an empty title', () {
      expect(eventTitleToSlug(''), 'event');
    });

    test('returns a fallback for a whitespace-only title', () {
      expect(eventTitleToSlug('   '), 'event');
    });

    test('returns a fallback for a null title', () {
      expect(eventTitleToSlug(null), 'event');
    });
  });
}
