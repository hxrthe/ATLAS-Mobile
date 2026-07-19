import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../student_dashboard/student_dashboard_screen.dart';
import '../faculty_dashboard/faculty_dashboard_screen.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';

class SignupScreen extends StatefulWidget {
  final String prefillEmail;
  final String prefillName;

  const SignupScreen({
    super.key,
    required this.prefillEmail,
    required this.prefillName,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _emailController;
  late final TextEditingController _nameController;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _courseController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();
  final TextEditingController _yearLevelController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  final Color primaryRed = const Color(0xFF8B1515);
  final Color darkText = const Color(0xFF1E232C);
  final Color grayText = const Color(0xFF8391A1);
  final Color borderColor = const Color(0xFFE8ECF4);
  final Color goldBorder = const Color(0xFFE5C07B);

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.prefillEmail);
    _nameController = TextEditingController(text: widget.prefillName);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _studentIdController.dispose();
    _courseController.dispose();
    _sectionController.dispose();
    _yearLevelController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    context.read<AuthBloc>().add(SignupRequested(
      email: _emailController.text,
      password: _passwordController.text,
      name: _nameController.text,
      studentId: _studentIdController.text,
      course: _courseController.text,
      section: _sectionController.text,
      yearLevel: _yearLevelController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthSuccess) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => state.role == 'faculty'
                    ? const FacultyDashboardScreen()
                    : const StudentDashboardScreen(),
              ),
              (route) => false,
            );
          } else if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: Colors.red.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: () async {
              _formKey.currentState?.reset();
              setState(() {});
            },
            child: SafeArea(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Back button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: darkText),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'Create Your Account',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fill in your details to get started.',
                      style: TextStyle(
                        fontSize: 14,
                        color: grayText,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ——— Institutional Email ———
                    _sectionLabel('INSTITUTIONAL EMAIL'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Institutional email is required' : null,
                      decoration: _inputDecoration(
                        hint: '24-00214@g.batstate-u.edu.ph',
                        prefixIcon: Icons.email_outlined,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ——— Full Name ———
                    _sectionLabel('FULL NAME'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                      decoration: _inputDecoration(
                        hint: 'Juan Dela Cruz',
                        prefixIcon: Icons.person_outline,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ——— Student ID (SR-CODE) ———
                    _sectionLabel('SR-CODE'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _studentIdController,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'SR-CODE is required' : null,
                      decoration: _inputDecoration(
                        hint: '24-00214',
                        prefixIcon: Icons.badge_outlined,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ——— Course & Section (side by side) ———
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('COURSE'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _courseController,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                                decoration: _inputDecoration(
                                  hint: 'BSIT',
                                  prefixIcon: Icons.school_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('SECTION'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _sectionController,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                                decoration: _inputDecoration(
                                  hint: 'CS-2101',
                                  prefixIcon: Icons.group_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ——— Year Level ———
                    _sectionLabel('YEAR LEVEL'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _yearLevelController,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Year level is required' : null,
                      decoration: _inputDecoration(
                        hint: '2',
                        prefixIcon: Icons.calendar_today_outlined,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ——— Password ———
                    _sectionLabel('PASSWORD'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 8) return 'At least 8 characters';
                        return null;
                      },
                      decoration: _inputDecoration(
                        hint: '••••••••',
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: grayText,
                          ),
                          onPressed: () =>
                              setState(() => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ——— Confirm Password ———
                    _sectionLabel('CONFIRM PASSWORD'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please confirm your password';
                        if (v != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                      decoration: _inputDecoration(
                        hint: '••••••••',
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: grayText,
                          ),
                          onPressed: () => setState(
                              () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: state is AuthLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        side: BorderSide(color: goldBorder, width: 2.0),
                        elevation: 0,
                        disabledBackgroundColor: primaryRed.withValues(alpha: 0.5),
                      ),
                      child: state is AuthLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'CREATE ACCOUNT',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Already have an account? Log in',
                        style: TextStyle(
                          color: primaryRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: grayText,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      prefixIcon: Icon(prefixIcon, color: grayText),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: borderColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: borderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: primaryRed, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }
}
