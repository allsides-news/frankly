import 'package:flutter/material.dart';
import 'package:client/styles/styles.dart';

/// A persistent toast notification using custom overlay that stays visible until dismissed
class PersistentFToast {
  static bool _isShowing = false;
  static OverlayEntry? _overlayEntry;

  /// Show a persistent toast notification
  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = Colors.red,
    Color textColor = Colors.white,
    VoidCallback? onDismiss,
    IconData? icon,
  }) {
    // Dismiss any existing toast
    dismiss();

    _isShowing = true;

    // Create a custom overlay entry for truly persistent toast
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 16.0,
        left: 24.0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width -
                  48.0, // Leave 24px padding on each side
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.0),
              color: backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon ?? Icons.person_add,
                  color: textColor,
                  size: 20,
                ),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: AppTextStyle.subhead.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    dismiss();
                    onDismiss?.call();
                  },
                  child: Icon(
                    Icons.close,
                    color: textColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Insert the overlay
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Dismiss the current persistent toast
  static void dismiss() {
    if (_overlayEntry != null && _isShowing) {
      try {
        _overlayEntry!.remove();
      } catch (e) {
        // Ignore errors when removing overlay
      }
      _overlayEntry = null;
      _isShowing = false;
    }
  }

  /// Check if a toast is currently showing
  static bool get isShowing => _isShowing;
}
