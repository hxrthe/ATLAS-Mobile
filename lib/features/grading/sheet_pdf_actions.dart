import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/atlas_alerts.dart';

enum SheetPdfAction { save, print, share }

String sheetPdfBaseName(String name) {
  final base = name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
  return '${base.isEmpty ? 'Exam' : base} answer sheet';
}

/// Builds the PDF with [build] and saves (system "Save as" → Downloads/Files),
/// prints, or shares it.
Future<void> runSheetPdfAction(
  BuildContext context, {
  required SheetPdfAction action,
  required Future<Uint8List> Function() build,
  required String name,
}) async {
  final base = sheetPdfBaseName(name);
  try {
    final bytes = await build();
    if (bytes.isEmpty) throw Exception('The answer sheet came back empty.');
    switch (action) {
      case SheetPdfAction.save:
        final saved = await FilePicker.saveFile(
          dialogTitle: 'Save answer sheet',
          fileName: '$base.pdf',
          bytes: bytes,
          mimeType: 'application/pdf',
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (saved != null && context.mounted) {
          AtlasAlerts.showSuccess(context, 'Answer sheet saved to your phone');
        }
      case SheetPdfAction.print:
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: base);
      case SheetPdfAction.share:
        await Printing.sharePdf(bytes: bytes, filename: '$base.pdf');
    }
  } catch (e) {
    if (context.mounted) {
      AtlasAlerts.showError(
        context,
        friendlyError(e, fallback: 'Could not prepare the answer sheet.'),
      );
    }
  }
}

/// Answer-sheet panel with an editable student ID length plus the three
/// actions. Returns the action and the chosen digit count.
Future<({SheetPdfAction action, int idDigits})?> pickSheetPdfOptions(
  BuildContext context, {
  required String title,
  required int idDigits,
  String? subtitle,
}) {
  return showModalBottomSheet<({SheetPdfAction action, int idDigits})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SheetOptionsPanel(
      title: title,
      subtitle: subtitle,
      initialDigits: idDigits.clamp(4, 8),
    ),
  );
}

class _SheetOptionsPanel extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int initialDigits;

  const _SheetOptionsPanel({
    required this.title,
    required this.initialDigits,
    this.subtitle,
  });

  @override
  State<_SheetOptionsPanel> createState() => _SheetOptionsPanelState();
}

class _SheetOptionsPanelState extends State<_SheetOptionsPanel> {
  late int _digits = widget.initialDigits;

  void _done(SheetPdfAction action) =>
      Navigator.pop(context, (action: action, idDigits: _digits));

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final changed = _digits != widget.initialDigits;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary),
            ),
            if (widget.subtitle != null)
              Text(widget.subtitle!, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: 18),
            Text('Student ID digits', style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  for (var d = 4; d <= 8; d++) ButtonSegment(value: d, label: Text('$d')),
                ],
                selected: {_digits},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _digits = s.first),
              ),
            ),
            if (changed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'The sheet will be updated to $_digits ID boxes. Reprint it — sheets '
                  'already printed with ${widget.initialDigits} boxes won\'t read correctly.',
                  style: TextStyle(fontSize: 12, color: c.ambiguous),
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _done(SheetPdfAction.save),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Save to phone', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _done(SheetPdfAction.print),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _done(SheetPdfAction.share),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
