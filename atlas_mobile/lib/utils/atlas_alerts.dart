import 'package:flutter/material.dart';

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
            Icon(Icons.check_circle, color: Theme.of(context).colorScheme.surfaceContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontWeight: FontWeight.bold))),
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
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.surfaceContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: primaryRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 3. ACTION CONFIRMATION DIALOG (Pops up in the center)
  /// Use this for submitting exams, deleting data, etc.
  static Future<void> showConfirmation({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    required VoidCallback onConfirm,
    bool isDestructive = false, // If true, makes the confirm button Red
  }) async {
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          title: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, color: isDestructive ? primaryRed : Colors.black87)
          ),
          content: Text(content),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog first
                onConfirm(); // Execute the passed function
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDestructive ? primaryRed : const Color(0xFF1E232C),
                foregroundColor: Theme.of(context).colorScheme.surfaceContainer,
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }
}