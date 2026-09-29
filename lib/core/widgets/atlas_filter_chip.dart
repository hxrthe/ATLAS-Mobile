import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FilterOption {
  final String value;
  final String label;
  final String? subtitle;

  const FilterOption(this.value, this.label, {this.subtitle});
}

/// One group of pills in [showAtlasFilterSheet]; a `null` selection means "All".
class FilterGroup {
  final String key;
  final String title;
  final String allLabel;
  final List<FilterOption> options;
  final String? hint;

  const FilterGroup({
    required this.key,
    required this.title,
    required this.options,
    this.allLabel = 'All',
    this.hint,
  });
}

/// Applied filter shown as a removable pill.
class AtlasAppliedChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const AtlasAppliedChip({super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: c.primary)),
          ),
          const SizedBox(width: 2),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 15, color: c.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrolling row of applied chips with a "Clear all" link.
class AtlasAppliedChipsRow extends StatelessWidget {
  final List<({String label, VoidCallback onRemove})> chips;
  final VoidCallback onClearAll;

  const AtlasAppliedChipsRow({
    super.key,
    required this.chips,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AtlasAppliedChip(label: chip.label, onRemove: chip.onRemove),
            ),
          if (chips.length > 1)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: onClearAll,
              child: const Text('Clear all', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// Tune icon with a badge counting active filters.
class AtlasFilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const AtlasFilterButton({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Badge(
      isLabelVisible: activeCount > 0,
      label: Text('$activeCount'),
      backgroundColor: c.primary,
      textColor: c.onPrimary,
      offset: const Offset(-4, 4),
      child: IconButton(
        tooltip: 'Filters',
        onPressed: onPressed,
        icon: Icon(Icons.tune_rounded, color: c.textPrimary),
      ),
    );
  }
}

/// Selectable rounded pill used inside filter sheets.
class AtlasFilterPill extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const AtlasFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? c.primary : c.border, width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 15, color: c.onPrimary),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? c.onPrimary : c.textPrimary)),
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: selected
                          ? c.onPrimary.withValues(alpha: 0.85)
                          : c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Shopping-app style filter sheet with pill groups, Reset and an apply button
/// whose label comes from [applyLabel] (e.g. "Show 12 students").
/// Returns the chosen selections keyed by [FilterGroup.key], or null if dismissed.
Future<Map<String, String?>?> showAtlasFilterSheet(
  BuildContext context, {
  required List<FilterGroup> groups,
  required Map<String, String?> initial,
  required String Function(Map<String, String?> draft) applyLabel,
}) {
  return showModalBottomSheet<Map<String, String?>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.atlas.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _AtlasFilterSheet(
      groups: groups,
      initial: initial,
      applyLabel: applyLabel,
    ),
  );
}

class _AtlasFilterSheet extends StatefulWidget {
  final List<FilterGroup> groups;
  final Map<String, String?> initial;
  final String Function(Map<String, String?> draft) applyLabel;

  const _AtlasFilterSheet({
    required this.groups,
    required this.initial,
    required this.applyLabel,
  });

  @override
  State<_AtlasFilterSheet> createState() => _AtlasFilterSheetState();
}

class _AtlasFilterSheetState extends State<_AtlasFilterSheet> {
  late final Map<String, String?> _draft = {
    for (final g in widget.groups) g.key: widget.initial[g.key],
  };

  int get _selectedCount => _draft.values.where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Text('Filters',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                if (_selectedCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$_selectedCount',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: c.onPrimary)),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: c.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.divider),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              children: [
                for (final g in widget.groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.title,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary)),
                        if (g.hint != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(g.hint!,
                                style: TextStyle(
                                    fontSize: 11.5, color: c.textSecondary)),
                          ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AtlasFilterPill(
                              label: g.allLabel,
                              selected: _draft[g.key] == null,
                              onTap: () => setState(() => _draft[g.key] = null),
                            ),
                            for (final o in g.options)
                              AtlasFilterPill(
                                label: o.label,
                                subtitle: o.subtitle,
                                selected: _draft[g.key] == o.value,
                                onTap: () =>
                                    setState(() => _draft[g.key] = o.value),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _selectedCount == 0
                        ? null
                        : () => setState(
                            () => _draft.updateAll((key, value) => null)),
                    child: Text('Reset',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: c.textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: c.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () =>
                        Navigator.pop(context, Map<String, String?>.of(_draft)),
                    child: Text(widget.applyLabel(_draft),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
