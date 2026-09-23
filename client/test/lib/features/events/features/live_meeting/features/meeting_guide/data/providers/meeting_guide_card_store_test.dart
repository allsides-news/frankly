import 'package:data_models/events/live_meetings/meeting_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hand-raise sentinel ids are valid Firestore document ids', () {
    for (final id in [startMeetingAgendaItemId, meetingWideAgendaItemId]) {
      expect(id, isNotEmpty);
      expect(id.contains('/'), isFalse);
      expect(id, isNot('.'));
      expect(id, isNot('..'));
      // Firestore: "Cannot match the regular expression __.*__"
      expect(RegExp(r'^__.*__$').hasMatch(id), isFalse);
    }
    expect(RegExp(r'^__.*__$').hasMatch('__meeting__'), isTrue);
  });
}
