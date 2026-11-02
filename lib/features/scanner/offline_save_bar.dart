import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'offline_pack.dart';

/// Floating notice near the top of the screen while exams are saved on the phone.
class OfflineSaveNotice extends StatelessWidget {
  const OfflineSaveNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfflineSaveProgress>(
      valueListenable: OfflinePack.progress,
      builder: (context, progress, _) {
        if (!progress.active) return const SizedBox.shrink();
        final c = context.atlas;
        final done = progress.finished;
        final accent = done ? c.correct : c.primary;
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: c.card,
                elevation: 8,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle
                            : Icons.cloud_download_outlined,
                        color: accent,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              done
                                  ? 'Saved on this phone'
                                  : 'Saving your exams and class lists',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              done
                                  ? 'You can scan even without internet.'
                                  : progress.known
                                      ? '${progress.percent}% saved'
                                      : 'This only takes a moment.',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                            if (!done) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progress.known
                                      ? progress.fraction
                                      : null,
                                  minHeight: 4,
                                  backgroundColor: c.border,
                                  color: accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
