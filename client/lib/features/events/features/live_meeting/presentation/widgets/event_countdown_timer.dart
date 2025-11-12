import 'package:flutter/material.dart';
import 'package:client/features/events/presentation/widgets/periodic_builder.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:data_models/events/event.dart';
import 'package:client/core/utils/date_utils.dart';

/// Widget that displays a countdown timer when an event is approaching its end time.
///
/// The countdown will:
/// - Show [minutesBeforeEnd] minutes before the event ends (default: 5 minutes)
/// - Update every second
/// - Change color to red in the last minute
/// - Automatically hide when the event ends or hasn't reached countdown threshold
class EventCountdownTimer extends StatelessWidget {
  final Event event;
  final int minutesBeforeEnd;

  const EventCountdownTimer({
    Key? key,
    required this.event,
    this.minutesBeforeEnd = 5,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PeriodicBuilder(
      period: Duration(seconds: 1),
      builder: (context) {
        final now = clockService.now();

        // Don't show if event shouldn't show countdown
        if (!event.shouldShowCountdown(now, minutesBefore: minutesBeforeEnd)) {
          return SizedBox.shrink();
        }

        final timeLeft = event.timeUntilEnd(now);
        final isLastMinute = timeLeft.inMinutes < 1;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isLastMinute
                ? context.theme.colorScheme.error
                : context.theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                color: isLastMinute
                    ? context.theme.colorScheme.onError
                    : context.theme.colorScheme.onErrorContainer,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Event ending in ${durationString(timeLeft)}',
                style: AppTextStyle.body.copyWith(
                  color: isLastMinute
                      ? context.theme.colorScheme.onError
                      : context.theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
