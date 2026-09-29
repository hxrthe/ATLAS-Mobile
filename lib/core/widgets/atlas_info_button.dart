import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Tinted circular "i" button that opens a card's detailed view.
class AtlasInfoButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const AtlasInfoButton({
    super.key,
    required this.onTap,
    this.tooltip = 'Detailed view',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.primary.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(Icons.info_outline_rounded, size: 20, color: c.primary),
          ),
        ),
      ),
    );
  }
}
