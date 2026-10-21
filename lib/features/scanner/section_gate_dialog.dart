import 'package:flutter/material.dart';
import '../../core/network/error_messages.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import 'scanner_widgets.dart';

/// Returned when the student was added to (or already found in) a section.
class SectionGateResult {
  final String studentId;
  final StudentBlock block;

  const SectionGateResult(this.studentId, this.block);
}

bool isUsableStudentId(String? id) {
  final v = (id ?? '').trim();
  return v.isNotEmpty && !v.contains('?') && v.toLowerCase() != 'unknown';
}

/// Popup shown when a scanned student ID is not on any section.
/// Resolves to null when the user disregards the scan.
Future<SectionGateResult?> showSectionGateDialog({
  required BuildContext context,
  required GradingRepository repository,
  required String? detectedId,
  required String courseId,
  required String examLabel,
  required Map<String, StudentBlock> knownBlocks,
  required List<SectionOption> sections,
  String? lastSectionId,
  String? lastGradeLevel,
}) {
  return showDialog<SectionGateResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SectionGateDialog(
      repository: repository,
      detectedId: detectedId,
      courseId: courseId,
      examLabel: examLabel,
      knownBlocks: knownBlocks,
      sections: sections,
      lastSectionId: lastSectionId,
      lastGradeLevel: lastGradeLevel,
    ),
  );
}

class _SectionGateDialog extends StatefulWidget {
  final GradingRepository repository;
  final String? detectedId;
  final String courseId;
  final String examLabel;
  final Map<String, StudentBlock> knownBlocks;
  final List<SectionOption> sections;
  final String? lastSectionId;
  final String? lastGradeLevel;

  const _SectionGateDialog({
    required this.repository,
    required this.detectedId,
    required this.courseId,
    required this.examLabel,
    required this.knownBlocks,
    required this.sections,
    this.lastSectionId,
    this.lastGradeLevel,
  });

  @override
  State<_SectionGateDialog> createState() => _SectionGateDialogState();
}

class _SectionGateDialogState extends State<_SectionGateDialog> {
  static const _newSection = '__new__';

  late final TextEditingController _idCtrl;
  late final TextEditingController _newSectionCtrl;
  late final TextEditingController _gradeCtrl;
  late final List<SectionOption> _courseSections;
  late final List<SectionOption> _otherSections;
  late final Map<String, String> _gradeBySectionId;
  String? _selectedSectionId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final detected = (widget.detectedId ?? '').trim();
    _idCtrl = TextEditingController(
      text: detected.toLowerCase() == 'unknown' ? '' : detected,
    );

    _gradeBySectionId = {};
    for (final b in widget.knownBlocks.values) {
      final id = b.sectionId;
      if (id == null || b.gradeLevel.isEmpty) continue;
      _gradeBySectionId.putIfAbsent(id, () => b.gradeLevel);
    }

    int byName(SectionOption a, SectionOption b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    _courseSections = widget.sections
        .where((s) => s.courseIds.contains(widget.courseId))
        .toList()
      ..sort(byName);
    _otherSections = widget.sections
        .where((s) => !s.courseIds.contains(widget.courseId))
        .toList()
      ..sort(byName);

    final allIds = widget.sections.map((s) => s.sectionId).toSet();
    final last = widget.lastSectionId;
    if (last != null && allIds.contains(last)) {
      _selectedSectionId = last;
    } else if (_courseSections.length == 1) {
      _selectedSectionId = _courseSections.first.sectionId;
    } else if (widget.sections.isEmpty) {
      _selectedSectionId = _newSection;
    }

    _newSectionCtrl = TextEditingController();
    _gradeCtrl = TextEditingController(
      text: _gradeBySectionId[_selectedSectionId] ?? widget.lastGradeLevel ?? '',
    );
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _newSectionCtrl.dispose();
    _gradeCtrl.dispose();
    super.dispose();
  }

  Future<void> _addAndRecord() async {
    final id = _idCtrl.text.trim();
    if (!isUsableStudentId(id)) {
      setState(() => _error = 'Enter the complete student ID (no "?" marks).');
      return;
    }
    final known = widget.knownBlocks[id];
    if (known != null && known.sectionId != null) {
      Navigator.pop(context, SectionGateResult(id, known));
      return;
    }
    final isNew = _selectedSectionId == _newSection;
    final newName = _newSectionCtrl.text.trim();
    if (_selectedSectionId == null || (isNew && newName.isEmpty)) {
      setState(() => _error = 'Choose a section${isNew ? ' name' : ''}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final block = await widget.repository.addStudentToSection(
        studentId: id,
        sectionId: isNew ? null : _selectedSectionId,
        sectionName: isNew ? newName : null,
        gradeLevel: _gradeCtrl.text.trim(),
        courseId: widget.courseId,
      );
      if (mounted) Navigator.pop(context, SectionGateResult(id, block));
    } on StudentInOtherSectionException catch (e) {
      // Already on a section, so the scan may be recorded as-is.
      if (mounted) Navigator.pop(context, SectionGateResult(id, e.existing));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(
          e,
          fallback: 'Could not add the student to the section. Please try again.',
        );
      });
    }
  }

  List<DropdownMenuItem<String>> _sectionItems() {
    DropdownMenuItem<String> item(SectionOption s, {bool takesCourse = false}) {
      return DropdownMenuItem(
        value: s.sectionId,
        child: Row(
          children: [
            Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
            if (takesCourse)
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
          ],
        ),
      );
    }

    return [
      ..._courseSections.map((s) => item(s, takesCourse: true)),
      ..._otherSections.map(item),
      const DropdownMenuItem(
        value: _newSection,
        child: Text('+ New section…',
            style: TextStyle(color: primaryRed, fontWeight: FontWeight.w600)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final detected = (widget.detectedId ?? '').trim();
    final readable = isUsableStudentId(detected);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group_off_rounded, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Student not on any section',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              readable
                  ? 'Student ID $detected is not yet on any section, so this scan '
                      'was not recorded.'
                  : 'The student ID on this sheet could not be read completely'
                      '${detected.isNotEmpty ? ' ("$detected")' : ''}, so it is not on any section.',
              style: const TextStyle(fontSize: 13.5, color: darkText, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              'Add it to a section for ${widget.examLabel} to record the score, '
              'or disregard this scan and scan the next paper.',
              style: const TextStyle(fontSize: 12.5, color: grayText, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _idCtrl,
              enabled: !_saving,
              decoration: _decoration('Student ID (SR code)', Icons.badge_outlined),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedSectionId,
              isExpanded: true,
              decoration: _decoration('Section', Icons.groups_2_outlined),
              hint: const Text('Choose a section'),
              items: _sectionItems(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                        _selectedSectionId = v;
                        final grade = _gradeBySectionId[v];
                        if (grade != null) _gradeCtrl.text = grade;
                      }),
            ),
            if (_courseSections.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text('✓ = section already takes this course',
                    style: TextStyle(fontSize: 11, color: grayText)),
              ),
            if (_selectedSectionId == _newSection) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _newSectionCtrl,
                enabled: !_saving,
                decoration: _decoration('New section name', Icons.add_box_outlined),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _gradeCtrl,
              enabled: !_saving,
              decoration: _decoration('Grade / year level (optional)', Icons.school_outlined),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: dangerRed, fontSize: 12.5)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Disregard & scan next', style: TextStyle(color: grayText)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: primaryRed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _saving ? null : _addAndRecord,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.person_add_alt_1, size: 18),
          label: Text(_saving ? 'Adding…' : 'Add & record'),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
