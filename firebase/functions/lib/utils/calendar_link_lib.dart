@JS()
library calendar_link;

import 'package:js/js.dart';
import 'package:node_interop/node.dart';

CalendarLinkLib requireCalendarLink() {
  return require('calendar-link') as CalendarLinkLib;
}

@JS()
@anonymous
class Event {
  external set title(String v);

  external String get title;

  external set description(String v);

  external String get description;

  external set start(String v);

  external String get start;

  external set end(String v);

  external String get end;

  external set organizer(Organizer v);

  external Organizer get organizer;
}

@JS()
@anonymous
class Organizer {
  external factory Organizer({String name, String email});
  
  external String get name;
  external set name(String v);
  
  external String get email;
  external set email(String v);
}

@JS()
@anonymous
abstract class CalendarLinkLib {
  external String google(Object e);

  external String outlook(Object e);

  external String office365(Object e);

  external String yahoo(Object e);

  external String ics(Object e);
}
