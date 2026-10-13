import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

String formatPercent(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';
}

String formatScore(double? raw, double? max) {
  String n(double? v) {
    if (v == null) return '—';
    return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
  }

  return '${n(raw)}/${n(max)}';
}

String formatShortDate(DateTime? d) {
  if (d == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '${months[l.month - 1]} ${l.day}, $h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

class QuickSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const QuickSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: c.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Prints two copies of the sheet per long-bond page (no header/footer).
class HalfPageSheetSwitch extends StatelessWidget {
  final bool value;
  final int totalItems;
  final bool locked;
  final ValueChanged<bool> onChanged;

  const HalfPageSheetSwitch({
    super.key,
    required this.value,
    required this.totalItems,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final fits = totalItems <= 40;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: locked || !fits ? null : onChanged,
      title: Text(
        'Half-page sheet',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary),
      ),
      subtitle: Text(
        fits
            ? 'No header or footer — 2 copies per 8.5×13 page, cut in half.'
            : 'Available for 40 items or fewer.',
        style: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
    );
  }
}

class QuickStatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const QuickStatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color ?? c.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Score chip coloured by pass/fail (amber when flagged).
class QuickScorePill extends StatelessWidget {
  final double? percent;
  final bool passed;
  final bool flagged;

  const QuickScorePill({
    super.key,
    required this.percent,
    required this.passed,
    this.flagged = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final color = flagged ? c.ambiguous : (passed ? c.pass : c.fail);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        formatPercent(percent),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class QuickEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const QuickEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: c.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class QuickErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const QuickErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.primary),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Horizontal subject filter: "All" plus one pill per subject.
class QuickSubjectChips extends StatelessWidget {
  final List<({String id, String label})> subjects;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final void Function(String id)? onLongPress;

  const QuickSubjectChips({
    super.key,
    required this.subjects,
    required this.selectedId,
    required this.onSelected,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _pill(context, null, 'All subjects'),
          for (final s in subjects) _pill(context, s.id, s.label),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String? id, String label) {
    final c = context.atlas;
    final selected = selectedId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(id),
        onLongPress:
            id == null || onLongPress == null ? null : () => onLongPress!(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.primary : c.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? c.primary : c.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? c.onPrimary : c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks an item as bonus: every paper gets the point.
class BonusKeyChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const BonusKeyChip({super.key, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          color: selected ? c.pass : Colors.transparent,
          border: Border.all(color: selected ? c.pass : c.border, width: 1.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: selected ? c.onPrimary : c.textSecondary),
            const SizedBox(width: 3),
            Text(
              'Bonus',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? c.onPrimary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
