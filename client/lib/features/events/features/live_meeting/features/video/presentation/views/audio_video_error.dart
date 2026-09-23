import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/utils/navigation_utils.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/video_capture_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:universal_html/html.dart' as html;

class AudioVideoErrorDialog extends StatelessWidget {
  final String error;
  final bool inMeeting;

  const AudioVideoErrorDialog({
    Key? key,
    required this.error,
    this.inMeeting = false,
  }) : super(key: key);

  static Future<T?> showOnError<T>(
    BuildContext context,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (e, s) {
      loggingService.log(
        'Error in audio/video',
        logType: LogType.error,
        error: e,
        stackTrace: s,
      );

      await showCustomDialog(
        context: context,
        builder: (_) => AudioVideoErrorDialog(error: e.toString()),
      );
      return null;
    }
  }

  static Future<void> show<T>(
    BuildContext context,
    String error, {
    bool inMeeting = false,
  }) async {
    await showCustomDialog(
      context: context,
      builder: (_) => AudioVideoErrorDialog(
        error: error,
        inMeeting: inMeeting,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // surfaceContainerLowest like the other in-meeting dialogs: the default
      // text below is onSurface, which is unreadable on `primary` (that pair
      // inverts with the theme).
      backgroundColor: context.theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: 700),
        child: Stack(
          children: [
            AudioVideoErrorDisplay(
              error: error,
              inMeeting: inMeeting,
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioVideoErrorDisplay extends StatelessWidget {
  const AudioVideoErrorDisplay({
    Key? key,
    required this.error,
    this.textColor,
    this.onJoinWithoutDevices,
    this.inMeeting = false,
  }) : super(key: key);

  final String error;
  final Color? textColor;
  final bool inMeeting;

  /// When set, permission/device errors are not a join wall: the user can
  /// continue listen-only instead of only Refresh (which re-hits the block).
  final VoidCallback? onJoinWithoutDevices;

  bool get _isDeviceError => isGetUserMediaError(error);

  bool get _canJoinWithoutDevices =>
      onJoinWithoutDevices != null && _isDeviceError;

  /// In-meeting device errors: stay in the call. Refresh reloads the page.
  bool get _showRefresh => audioVideoErrorShowsRefresh(
        inMeeting: inMeeting,
        isDeviceError: _isDeviceError,
      );

  String _buildErrorText(BuildContext context) {
    // AppLocalizations.of, not context.l10n: that helper writes GetIt and
    // throws if AppLocalizationService is not registered yet.
    final l10n = AppLocalizations.of(context)!;
    String errorText = error;
    if (errorText.contains('NotReadableError')) {
      errorText = l10n.avErrorNotReadable;
    } else if (errorText.contains('NotFoundError')) {
      errorText = l10n.avErrorNotFound;
    } else if (['OverconstrainedError', 'TypeError']
        .any((error) => errorText.contains(error))) {
      errorText = l10n.avErrorMediaAccess;
    } else if (errorText.contains('NotAllowedError')) {
      errorText = audioVideoErrorUsesListenOnlyCopy(
        inMeeting: inMeeting,
        canJoinWithoutDevices: _canJoinWithoutDevices,
      )
          ? l10n.avErrorListenOnly
          : l10n.avErrorPermissionRequired;
    } else if (errorText.contains('TwilioError')) {
      errorText = l10n.avErrorDisconnected;
    } else if (errorText
        .toLowerCase()
        .contains('Invalid constraints'.toLowerCase())) {
      errorText = l10n.avErrorConstraints;
    } else if (errorText.contains('TimeoutException')) {
      errorText = l10n.avErrorNetwork;
    }

    if (errorText.contains(
      'TwilioError: Participant disconnected because of duplicate identity',
    )) {
      errorText = l10n.avErrorDuplicateIdentity;
    }

    return errorText;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Linkify(
            onOpen: (link) => launch(link.url),
            options: LinkifyOptions(
              humanize: false,
              removeWww: false,
            ),
            text: _buildErrorText(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor ?? context.theme.colorScheme.onSurface,
              fontSize: 22,
            ),
          ),
          SizedBox(height: 16),
          if (_canJoinWithoutDevices) ...[
            ActionButton(
              text: l10n.avErrorJoinWithoutDevices,
              onPressed: onJoinWithoutDevices,
            ),
            SizedBox(height: 12),
          ],
          if (_showRefresh)
            ActionButton(
              text: l10n.refresh,
              onPressed: () => html.window.location.reload(),
            )
          else
            ActionButton(
              text: l10n.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}
