import 'package:client/core/utils/web_utils.dart';
import 'package:intl/intl.dart';

String dateTimeFormat({required DateTime date}) {
  var formattedDate = DateFormat('MMM d yyyy, h:mma').format(date);
  return formattedDate;
}

/// An event's time in the app's compact form: "4:00p", with the timezone
/// abbreviation appended when one is available ("4:00p CDT").
///
/// The lowercased, trailing-'m'-less meridiem is the house style used by the
/// event cards; this is the single definition of it.
String eventTimeFormat(DateTime time) {
  final formatted = DateFormat('h:mma').format(time);
  final compact = formatted.substring(0, formatted.length - 1).toLowerCase();
  final timezone = getTimezoneAbbreviation(time);

  if (timezone == null || timezone.isEmpty) return compact;
  return '$compact $timezone';
}

int differenceInDays(DateTime a, DateTime b) {
  return dateTimeWithoutTime(a).difference(dateTimeWithoutTime(b)).inDays;
}

DateTime dateTimeWithoutTime(DateTime d) {
  return DateTime(d.year, d.month, d.day);
}

String durationString(Duration duration, {bool readAsHuman = false}) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
  final String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
  if (duration.inHours > 0) {
    final timeString = readAsHuman
        ? '${duration.inHours} hr ${int.parse(twoDigitMinutes) > 0 ? '$twoDigitMinutes min' : ''}'
        : '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';

    return timeString;
  } else {
    return readAsHuman
        ? '$twoDigitMinutes min'
        : '$twoDigitMinutes:$twoDigitSeconds';
  }
}
