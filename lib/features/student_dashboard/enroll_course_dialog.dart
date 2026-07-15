import 'package:flutter/material.dart';

class EnrollCourseDialog extends StatefulWidget {
  final void Function(String courseCode) onEnroll;

  const EnrollCourseDialog({super.key, required this.onEnroll});

  @override
  State<EnrollCourseDialog> createState() => _EnrollCourseDialogState();
}

class _EnrollCourseDialogState extends State<EnrollCourseDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  final Color primaryRed = const Color(0xFF8B1515);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a course code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    widget.onEnroll(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Join a Course',
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E232C)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the course code provided by your instructor to enroll.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Course Code',
              hintText: 'e.g. IT301',
              prefixIcon: const Icon(Icons.code),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryRed, width: 2),
              ),
              errorText: _error,
            ),
            onSubmitted: (_) => _loading ? null : _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF8391A1), fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enroll', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
