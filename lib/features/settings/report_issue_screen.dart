import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final TextEditingController _issueController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _includePhone = true;
  bool _isSubmitting = false;
  XFile? _screenshot;

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file == null || !mounted) return;
      setState(() => _screenshot = file);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the photo picker. Check app permissions.'),
        ),
      );
    }
  }

  void _showPickerSheet() {
    final colors = context.atlas;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: colors.primary),
                  title: Text('Choose from gallery',
                      style: TextStyle(color: colors.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickScreenshot(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_camera_outlined, color: colors.primary),
                  title: Text('Take a photo',
                      style: TextStyle(color: colors.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickScreenshot(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitReport() async {
    final message = _issueController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tell us what happened.')),
      );
      return;
    }
    if (_screenshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a screenshot of the issue.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String note = '';
      if (_includePhone) {
        final info = await PackageInfo.fromPlatform();
        final phone = Platform.isIOS ? 'iPhone' : 'Android';
        note = '$phone · app ${info.version}';
      }
      final form = FormData.fromMap({
        'message': message,
        if (note.isNotEmpty) 'phone_note': note,
        'image': await MultipartFile.fromFile(
          _screenshot!.path,
          filename: _screenshot!.name.isNotEmpty
              ? _screenshot!.name
              : 'screenshot.jpg',
        ),
      });
      final response = await ApiClient().dio.post(
        'auth/support-reports/',
        data: form,
      );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final delivered =
          response.data is Map ? response.data['delivered_to'] : null;
      final sentToTeam = delivered == 'superadmin';
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Report sent',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (dialogContext, anim, secondary) {
          return const SizedBox.shrink();
        },
        transitionBuilder: (dialogContext, anim, secondary, child) {
          final colors = dialogContext.atlas;
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1).animate(curved),
              child: Center(
                child: Material(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.6, end: 1),
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Transform.scale(scale: value, child: child);
                            },
                            child: Icon(
                              Icons.check_circle,
                              color: colors.correct,
                              size: 56,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            sentToTeam
                                ? 'Your message was sent to the ATLAS team.'
                                : 'Your message was sent to your campus admin. They can pass it to the ATLAS team if more help is needed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              Navigator.pop(context);
                            },
                            child: Text(
                              'OK',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(
              e,
              fallback:
                  'We could not send this right now. Check your internet and try again.',
            ),
          ),
        ),
      );
    }
  }

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
          'Report an Issue',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your campus admin will read this. They can send it on to the ATLAS team if the campus needs more help.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'WHAT HAPPENED',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _issueController,
              maxLines: 8,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText:
                    'Tell us what you were trying to do and what happened instead. Everyday words are enough.',
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
                filled: true,
                fillColor: colors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'SCREENSHOT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Required. Add a photo of the problem so your campus admin can see it.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_screenshot == null)
              OutlinedButton.icon(
                onPressed: _showPickerSheet,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add screenshot'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Image.file(
                        File(_screenshot!.path),
                        fit: BoxFit.cover,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: _showPickerSheet,
                            child: Text('Replace',
                                style: TextStyle(color: colors.primary)),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _screenshot = null),
                            child: Text('Remove',
                                style: TextStyle(color: colors.incorrect)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colors.cardMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.smartphone_outlined, color: colors.textSecondary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Include my phone details',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'The kind of phone and the app version, so we know which copy you are using.',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: _includePhone,
                    onChanged: (val) =>
                        setState(() => _includePhone = val ?? true),
                    activeColor: colors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: colors.onPrimary,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'SEND REPORT',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
