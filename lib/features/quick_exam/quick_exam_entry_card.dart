import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'quick_exam_hub_screen.dart';

/// Entry to the Major Examination hub (Home and Courses tabs).
class QuickExamEntryCard extends StatelessWidget {
  const QuickExamEntryCard({super.key});

  Future<void> _open(BuildContext context, {bool startWithNew = false}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickExamHubScreen(startWithNew: startWithNew),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: c.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.quiz_outlined, color: c.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Major Examination',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Create new exams here for your courses.',
                          style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open(context, startWithNew: true),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _open(context),
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
