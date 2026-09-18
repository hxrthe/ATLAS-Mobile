import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class AtlasAlerts {
  // Brand Colors
  static const Color primaryRed = Color(0xFF8B1515);
  static const Color successGreen = Color(0xFF198754);

  /// 1. SUCCESS SNACKBAR (Slides up from the bottom)
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 2. ERROR SNACKBAR (Slides up from the bottom)
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: primaryRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static Future<void> showConfirmation({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) async {
    final colors = context.atlas;
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final d = dialogContext.atlas;
        return AlertDialog(
          backgroundColor: d.card,
          title: Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDestructive ? primaryRed : d.textPrimary)),
          content: Text(content, style: TextStyle(color: d.textSecondary)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel',
                  style: TextStyle(
                      color: d.textSecondary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onConfirm();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDestructive ? primaryRed : colors.textPrimary,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }
}
