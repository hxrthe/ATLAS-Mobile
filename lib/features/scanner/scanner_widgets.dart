import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../grading/models.dart';
import 'omr_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Section Selection Sheet
// ═══════════════════════════════════════════════════════════════════════════

class SectionSelectionSheet extends StatefulWidget {
  final String courseId;
  final String courseName;
  final List<BubbleTemplate> templates;
  final String? defaultSection;
  final void Function(String section)? onSectionSaved;

  const SectionSelectionSheet({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.templates,
    this.defaultSection,
    this.onSectionSaved,
  });

  @override
  State<SectionSelectionSheet> createState() => _SectionSelectionSheetState();
}

class _SectionSelectionSheetState extends State<SectionSelectionSheet> {
  BubbleTemplate? _selected;
  int? _selectedPartIndex;
  late TextEditingController _sectionController;
  bool _hasDefaultSection = false;

  @override
  void initState() {
    super.initState();
    _hasDefaultSection = widget.defaultSection != null && widget.defaultSection!.isNotEmpty;
    _sectionController = TextEditingController(text: widget.defaultSection ?? '');
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Iterable<MapEntry<int, BubblePart>> get _parts {
    if (_selected == null) return const Iterable.empty();
    return _selected!.parts.asMap().entries;
  }

  @override
  Widget build(BuildContext context) {
    final primaryRed = const Color(0xFF8B1515);
    final grayText = const Color(0xFF8391A1);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6F9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Choose Section / Block',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E232C),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.courseName,
              style: TextStyle(fontSize: 13, color: grayText),
            ),
          ),
          const SizedBox(height: 8),

          // Section / Block field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sectionController,
                    decoration: InputDecoration(
                      labelText: 'Section / Block',
                      hintText: 'e.g. BSIT-3A',
                      prefixIcon: const Icon(Icons.group, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: primaryRed, width: 2),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                if (!_hasDefaultSection)
                  SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () {
                        final section = _sectionController.text.trim();
                        if (section.isNotEmpty) {
                          widget.onSectionSaved?.call(section);
                          setState(() => _hasDefaultSection = true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Template picker
          if (widget.templates.length > 1) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'ASSESSMENT',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: grayText,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: widget.templates.length,
                separatorBuilder: (_, _a) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final t = widget.templates[i];
                  final active = _selected?.templateId == t.templateId;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selected = t;
                      _selectedPartIndex = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? primaryRed : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active ? primaryRed : const Color(0xFFE8ECF4),
                        ),
                      ),
                      child: Text(
                        t.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : const Color(0xFF1E232C),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Section / Part list
          if (_selected != null && _parts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'SECTION / BLOCK',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: grayText,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _parts.length,
                separatorBuilder: (_, _a) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final part = _parts.elementAt(i).value;
                  final active = _selectedPartIndex == i;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedPartIndex = i),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: active ? primaryRed.withOpacity(0.08) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? primaryRed : const Color(0xFFE8ECF4),
                          width: active ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: active
                                  ? primaryRed
                                  : const Color(0xFFF4F6F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: active ? Colors.white : grayText,
                                  )),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  part.label.isNotEmpty
                                      ? part.label
                                      : 'Block ${i + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: active
                                        ? primaryRed
                                        : const Color(0xFF1E232C),
                                  ),
                                ),
                                Text(
                                  'Items ${part.startItem}–${part.endItem}',
                                  style:
                                      TextStyle(fontSize: 11, color: grayText),
                                ),
                              ],
                            ),
                          ),
                          if (active)
                            Icon(Icons.check_circle,
                                color: primaryRed, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else if (_selected != null && _parts.isEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('No sections defined. Scanning the entire assessment.',
                  style: TextStyle(fontSize: 13, color: grayText)),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.templates.isEmpty
                    ? 'No templates available for this course.'
                    : 'Select an assessment above to view sections.',
                style: TextStyle(fontSize: 13, color: grayText),
              ),
            ),
          ],

          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ElevatedButton.icon(
              onPressed: _selected != null
                  ? () {
                      Navigator.pop(context, {
                        'template': _selected,
                        'part_index': _selectedPartIndex,
                        'section': _sectionController.text.trim(),
                      });
                    }
                  : null,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start Scanning',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Template Selection View
// ═══════════════════════════════════════════════════════════════════════════

class TemplateSelectionView extends StatelessWidget {
  final List<BubbleTemplate> templates;
  final BubbleTemplate? selectedTemplate;
  final bool isLoading;
  final bool isLoadingDetail;
  final String? error;
  final String? courseName;
  final void Function(BubbleTemplate) onTemplateSelected;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;
  final VoidCallback onStartScan;
  final VoidCallback onBack;
  final Color primaryRed;
  final Color darkText;
  final Color grayText;
  final Color borderColor;
  final Color bgGrey;

  const TemplateSelectionView({
    super.key,
    required this.templates,
    required this.selectedTemplate,
    required this.isLoading,
    this.isLoadingDetail = false,
    this.error,
    this.courseName,
    required this.onTemplateSelected,
    required this.onRetry,
    required this.onRefresh,
    required this.onStartScan,
    required this.onBack,
    required this.primaryRed,
    required this.darkText,
    required this.grayText,
    required this.borderColor,
    required this.bgGrey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgGrey,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: darkText),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Text('Select Assessment',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: darkText)),
              ],
            ),
            if (courseName != null) ...[
              const SizedBox(height: 8),
              Text(courseName!, style: TextStyle(fontSize: 14, color: grayText)),
            ],
            const SizedBox(height: 24),
            if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (error != null && templates.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: primaryRed),
                      const SizedBox(height: 12),
                      Text(error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: primaryRed, fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            if (!isLoading && error == null && templates.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No bubble sheet templates found.\nCreate one from the web dashboard first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8391A1), fontSize: 14),
                  ),
                ),
              ),
            if (!isLoading && templates.isNotEmpty) ...[
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => onRefresh(),
                  child: ListView.separated(
                    itemCount: templates.length,
                    separatorBuilder: (_, _a) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final t = templates[index];
                      final isSelected =
                          selectedTemplate?.templateId == t.templateId;
                      return GestureDetector(
                        onTap: () => onTemplateSelected(t),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? primaryRed : borderColor,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: primaryRed.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.assignment,
                                        color: primaryRed, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(t.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Colors.black87)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${t.totalItems} items \u00b7 ${t.numChoices} choices \u00b7 ${t.hasAnswerKey ? "Key set" : "No key"}',
                                          style: TextStyle(
                                              fontSize: 12, color: grayText),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected && isLoadingDetail)
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: primaryRed),
                                    ),
                                  if (!isLoadingDetail && isSelected)
                                    Icon(Icons.check_circle,
                                        color: primaryRed, size: 24),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildKeyBadge(t),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Pull down to refresh',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: grayText)),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed:
                    selectedTemplate != null && !isLoadingDetail ? onStartScan : null,
                icon: const Icon(Icons.camera_alt),
                label: isLoadingDetail
                    ? const Text('Loading answer key…',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))
                    : const Text('Start Scanning',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeyBadge(BubbleTemplate t) {
    if (t.hasAnswerKey && t.assessmentId != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 12, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text('Assessment key \u2713',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700)),
          ],
        ),
      );
    }
    if (t.hasAnswerKey) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Text('Manual key \u2713',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700)),
      );
    }
    if (t.assessmentId != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: GestureDetector(
          onTap: () => onTemplateSelected(t),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync, size: 12, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text('No key — tap to sync',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700)),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text('No answer key',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.red.shade600)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Capture View
// ═══════════════════════════════════════════════════════════════════════════

class CaptureView extends StatelessWidget {
  final CameraController? controller;
  final bool isReady;
  final String templateName;
  final VoidCallback onBack;
  final VoidCallback onCapture;
  final Color primaryRed;
  final Color goldBorder;

  const CaptureView({
    super.key,
    required this.controller,
    required this.isReady,
    required this.templateName,
    required this.onBack,
    required this.onCapture,
    required this.primaryRed,
    required this.goldBorder,
  });

  @override
  Widget build(BuildContext context) {
    if (!isReady || controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8B1515)));
    }

    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(controller!)),
        Positioned(
          top: 0, left: 0, right: 0,
          child: _topBar(),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 100),
            decoration: BoxDecoration(
              border: Border.all(color: goldBorder, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 48, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: onCapture,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: Center(
                  child: Container(
                    width: 60, height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black54,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Align Exam Sheet',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(templateName,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Processing View
// ═══════════════════════════════════════════════════════════════════════════

class ProcessingView extends StatelessWidget {
  final bool isUploading;
  final bool isProcessingLocally;
  final String? stage;
  final Color darkText;
  final Color grayText;
  final Color bgGrey;
  final Color primaryRed;

  const ProcessingView({
    super.key,
    required this.isUploading,
    this.isProcessingLocally = false,
    this.stage,
    required this.darkText,
    required this.grayText,
    required this.bgGrey,
    required this.primaryRed,
  });

  @override
  Widget build(BuildContext context) {
    final label = isProcessingLocally
        ? (stage ?? 'Scanning…')
        : (isUploading ? 'Uploading and grading...' : 'Processing scan...');

    return Container(
      color: bgGrey,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryRed),
            const SizedBox(height: 24),
            Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: darkText),
            ),
            const SizedBox(height: 8),
            Text(
              isProcessingLocally ? 'Grading on-device, no network needed' : 'This may take a few seconds',
                style: TextStyle(fontSize: 13, color: grayText)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Result View
// ═══════════════════════════════════════════════════════════════════════════

class ResultView extends StatelessWidget {
  final BubbleScan? scan;
  final String? error;
  final BubbleTemplate? selectedTemplate;
  final bool isUploading;
  final OmrResult? omrResult;
  final VoidCallback onScanAnother;
  final VoidCallback onDone;
  final VoidCallback? onUpload;
  final Color primaryRed;
  final Color darkText;
  final Color grayText;
  final Color bgGrey;

  const ResultView({
    super.key,
    this.scan,
    this.error,
    this.selectedTemplate,
    this.isUploading = false,
    this.omrResult,
    required this.onScanAnother,
    required this.onDone,
    this.onUpload,
    required this.primaryRed,
    required this.darkText,
    required this.grayText,
    required this.bgGrey,
  });

  bool get _isUploaded => scan != null && scan!.scanId.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgGrey,
      child: Column(
        children: [
          _header(),
          if (scan != null) Expanded(child: _content()),
          if (error != null && scan == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber, size: 48, color: primaryRed),
                      const SizedBox(height: 16),
                      Text(error!, textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: darkText, height: 1.5)),
                    ],
                  ),
                ),
              ),
            ),
          _bottomActions(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      color: scan != null ? primaryRed : Colors.orange.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              scan != null ? Icons.check_circle : Icons.error,
              color: Colors.white, size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scan != null ? 'Scan Complete' : 'Scan Failed',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    scan != null ? 'Student: ${scan!.studentIdentifier}' : (error ?? 'Unknown error'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final s = scan!;
    final sp = s.scorePercent;
    final score = sp != null ? '${sp.toStringAsFixed(1)}%' : 'N/A';
    final raw = s.scoreRaw != null && s.maxScore != null
        ? '${s.scoreRaw!.toStringAsFixed(0)} / ${s.maxScore!.toStringAsFixed(0)}'
        : null;
    final passing = selectedTemplate?.passingScore;
    final isPass = sp != null && passing != null && sp >= passing;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Score card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Text(score,
                    style: TextStyle(
                        fontSize: 48, fontWeight: FontWeight.w900,
                        color: isPass ? Colors.green.shade700 : primaryRed)),
                if (raw != null) ...[
                  const SizedBox(height: 4),
                  Text(raw, style: TextStyle(fontSize: 14, color: grayText)),
                ],
                if (passing != null) ...[
                  const SizedBox(height: 8),
                  Text('Passing: ${passing.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF8391A1))),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Confidence legend
          if (omrResult != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Confidence Levels',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8391A1))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      _legendDot(Colors.green.shade700, 'Confirmed'),
                      _legendDot(Colors.green.shade600, 'Acceptable'),
                      _legendDot(Colors.orange.shade600, 'Ambiguous'),
                      _legendDot(Colors.red.shade600, 'Wrong'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Responses grid
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Item Responses',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E232C))),
                const SizedBox(height: 12),
                if (selectedTemplate != null && selectedTemplate!.answerKey.isNotEmpty)
                  _buildResponsesGrid(s, selectedTemplate!)
                else
                  Text('${s.responses.length} items scanned',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF8391A1))),
              ],
            ),
          ),

          if (s.isFlagged) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.flagReason ?? 'Sheet flagged for review.',
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade900)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Build the responses grid with 4-state confidence display:
  ///   Confirmed (fill ≥ 0.42) → green bold border
  ///   Acceptable (0.28–0.42) → green light
  ///   Ambiguous (?) → orange
  ///   Wrong → red
  Widget _buildResponsesGrid(BubbleScan s, BubbleTemplate template) {
    // Build a lookup map from item numbers to BubbleReading
    final readingMap = <String, BubbleReading>{};
    if (omrResult != null) {
      for (final r in omrResult!.readings) {
        readingMap[r.itemNumber.toString()] = r;
      }
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: s.responses.entries.map((entry) {
        final item = entry.key;
        final resp = entry.value;
        final correct = template.answerKey[item];
        final ok = resp == correct;
        final amb = resp == '?';
        final rd = readingMap[item];
        final confirmed = rd?.isConfirmed == true;

        Color bg;
        Color bd;
        Color fg;
        FontWeight weight;

        if (amb) {
          bg = Colors.orange.shade50;
          bd = Colors.orange.shade300;
          fg = Colors.orange.shade700;
          weight = FontWeight.bold;
        } else if (ok) {
          if (confirmed) {
            bg = Colors.green.shade100;
            bd = Colors.green.shade700;
            fg = Colors.green.shade800;
            weight = FontWeight.w900;
          } else {
            bg = Colors.green.shade50;
            bd = Colors.green.shade300;
            fg = Colors.green.shade700;
            weight = FontWeight.bold;
          }
        } else {
          bg = Colors.red.shade50;
          bd = Colors.red.shade300;
          fg = Colors.red.shade700;
          weight = FontWeight.bold;
        }

        return Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bd, width: confirmed ? 2 : 1),
          ),
          child: Column(
            children: [
              Text(item,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: grayText)),
              const SizedBox(height: 2),
              Text(resp,
                  style: TextStyle(fontSize: 15, fontWeight: weight, color: fg)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8391A1))),
      ],
    );
  }

  Widget _bottomActions() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (scan != null && !_isUploaded && onUpload != null) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Graded on-device. Upload to sync with server.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: isUploading ? null : onUpload,
                icon: isUploading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload),
                label: Text(isUploading ? 'Uploading…' : 'Upload to Server'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onScanAnother,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan Another'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryRed,
                      side: BorderSide(color: primaryRed),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (scan != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onDone,
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}