DateTime? dateTimeFromTimestamp(dynamic timestamp) {
  if (timestamp == null) {
    return null;
  } else if (timestamp is String) {
    // Handle SERVER_TIMESTAMP placeholder - return null if not yet set
    if (timestamp == serverTimestampValue) {
      return null;
    }
    return DateTime.parse(timestamp);
  } else if (timestamp is DateTime?) {
    return timestamp;
  }
  return null;
}

// This no longer does anything, as functions and client handle this conversion on their own
dynamic timestampFromDateTime(DateTime? dateTime) => dateTime;

const String serverTimestampValue = 'SERVER_TIMESTAMP';

dynamic serverTimestamp(DateTime? dateTime) => serverTimestampValue;

dynamic serverTimestampOrNull(DateTime? dateTime) =>
    dateTime == null ? null : serverTimestampValue;
