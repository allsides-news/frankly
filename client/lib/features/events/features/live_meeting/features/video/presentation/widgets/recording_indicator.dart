import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/video_overlay_colors.dart';
import 'package:flutter/material.dart';

/// Tells the room it is being recorded.
///
/// One definition, used by the desktop and mobile meeting views. There were
/// two copies, identical but for the colour they drew the label in, which is
/// why the same indicator was unreadable in different ways on each.
///
/// Drawn on the same plate as every other video overlay -- see
/// [VideoOverlayColors] for why those are constants rather than theme tokens.
class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({Key? key}) : super(key: key);

  /// Reinforces the label; the word "Recording" beside it is what actually
  /// carries the meaning, so this doesn't have to meet the 3:1 that a
  /// standalone indicator would.
  static const Color _pulse = Color(0xFFFF4438);

  static const double _pulseSize = 16;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'This meeting is being recorded',
      liveRegion: true,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: VideoOverlayColors.plate,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: _pulseSize,
              width: _pulseSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _pulse,
              ),
            ),
            SizedBox(width: 8),
            HeightConstrainedText(
              'Recording',
              style: TextStyle(color: VideoOverlayColors.onPlate),
            ),
          ],
        ),
      ),
    );
  }
}
