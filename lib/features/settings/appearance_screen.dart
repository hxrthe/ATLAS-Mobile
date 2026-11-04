import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/font_scale_controller.dart';
import '../../core/theme/theme_controller.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Appearance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'THEME',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: themeController,
            builder: (context, _) {
              final dark = themeController.mode == ThemeMode.dark;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  dark ? Icons.dark_mode : Icons.light_mode,
                  color: colors.textSecondary,
                ),
                title: Text(
                  'Dark mode',
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  dark
                      ? 'Using results-style dark palette'
                      : 'Using light campus palette',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                value: dark,
                onChanged: (v) => themeController
                    .setMode(v ? ThemeMode.dark : ThemeMode.light),
              );
            },
          ),
          Divider(height: 40, color: colors.divider),
          Text(
            'TEXT SIZE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Larger text for easier reading. Layout stays clear at every size.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: fontScaleController,
            builder: (context, _) => _TextSizeSlider(
              index: fontScaleController.scaleIndex,
              onChanged: fontScaleController.setScaleIndex,
            ),
          ),
          const SizedBox(height: 28),
          ListenableBuilder(
            listenable: fontScaleController,
            builder: (context, _) {
              final label = FontScaleController.labeledScales
                  .firstWhere(
                    (e) => e.$1 == fontScaleController.scale,
                    orElse: () => (fontScaleController.scale, 'Custom'),
                  )
                  .$2;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preview · $label',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Course titles and scores stay readable.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Secondary details wrap without clipping the screen.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TextSizeSlider extends StatelessWidget {
  const _TextSizeSlider({
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    final divisions = FontScaleController.allowedScales.length - 1;
    return Column(
      children: [
        Row(
          children: [
            Text(
              'Aa',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: colors.border,
                  thumbColor: colors.primary,
                  overlayColor: colors.primary.withValues(alpha: 0.12),
                  trackHeight: 3,
                  tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 3),
                  activeTickMarkColor: colors.onPrimary,
                  inactiveTickMarkColor: colors.textSecondary.withValues(alpha: 0.45),
                ),
                child: Slider(
                  value: index.toDouble(),
                  min: 0,
                  max: divisions.toDouble(),
                  divisions: divisions,
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
            ),
            Text(
              'Aa',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < FontScaleController.labeledScales.length; i++)
                Text(
                  FontScaleController.labeledScales[i].$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                    color: i == index ? colors.primary : colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
