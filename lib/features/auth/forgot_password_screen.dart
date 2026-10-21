import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import '../../core/theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final PageController _pageController = PageController();
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  String? _resetToken;
  bool _resendEnabled = false;
  int _resendCooldown = 30;
  Timer? _cooldownTimer;

  static const _leaf = Color(0xFF15803D);
  static const _darkBg = Color(0xFF0A0A0B);

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() {
      _resendEnabled = false;
      _resendCooldown = 30;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendEnabled = true);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _resendCode() {
    if (!_resendEnabled) return;
    _startCooldown();
    context.read<AuthBloc>().add(
      ForgotPasswordRequested(email: _emailController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final colors = context.atlas;
    final bg = isDark ? _darkBg : Colors.white;
    final accent = isDark ? const Color(0xFF16A34A) : _leaf;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is ForgotPasswordEmailSent) {
            _startCooldown();
            _nextPage();
          } else if (state is OtpVerified) {
            _resetToken = state.resetToken;
            _nextPage();
          } else if (state is PasswordResetSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Password reset successful. Please login.')),
            );
            Navigator.pop(context);
          } else if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error), backgroundColor: Colors.red),
            );
          }
        },
        builder: (context, state) {
          return PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildEmailStep(state, colors, accent),
              _buildOtpStep(state, colors, accent),
              _buildResetStep(state, colors, accent),
            ],
          );
        },
      ),
    );
  }

  // ── Step 1: Email ──

  Widget _buildEmailStep(AuthState state, AtlasColors colors, Color accent) {
    return Form(
      key: _emailFormKey,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Forgot Password?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Don't worry! It occurs. Please enter the email address linked with your account.",
              style: TextStyle(color: colors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              style: TextStyle(color: colors.textPrimary),
              decoration: _inputDecoration('Enter your email', colors, accent),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Email is required';
                }
                final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                if (!emailRegex.hasMatch(value.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            _buildButton(
              text: 'Send Code',
              accent: accent,
              isLoading: state is AuthLoading,
              onPressed: () {
                if (_emailFormKey.currentState!.validate()) {
                  context.read<AuthBloc>().add(
                    ForgotPasswordRequested(email: _emailController.text.trim()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: OTP ──

  Widget _buildOtpStep(AuthState state, AtlasColors colors, Color accent) {
    return Form(
      key: _otpFormKey,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'OTP Verification',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Enter the verification code we just sent on your email address.",
              style: TextStyle(color: colors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              style: TextStyle(color: colors.textPrimary),
              decoration:
                  _inputDecoration('Enter verification code', colors, accent),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'OTP is required';
                }
                if (value.trim().length < 4) {
                  return 'OTP must be at least 4 digits';
                }
                if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
                  return 'OTP must contain only digits';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            _buildButton(
              text: 'Verify',
              accent: accent,
              isLoading: state is AuthLoading,
              onPressed: () {
                if (_otpFormKey.currentState!.validate()) {
                  context.read<AuthBloc>().add(
                    VerifyOtpRequested(
                      email: _emailController.text.trim(),
                      otp: _otpController.text.trim(),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            Center(
              child: _resendEnabled
                  ? TextButton(
                      onPressed: _resendCode,
                      child: Text(
                        'Resend Code',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Text(
                      'Resend code in $_resendCooldown s',
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 3: New Password ──

  Widget _buildResetStep(AuthState state, AtlasColors colors, Color accent) {
    return Form(
      key: _resetFormKey,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create New Password',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Your new password must be unique from those previously used.",
              style: TextStyle(color: colors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: colors.textPrimary),
              decoration: _inputDecoration('New Password', colors, accent)
                  .copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible ? Icons.visibility_off : Icons.visibility,
                    color: colors.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: !_confirmPasswordVisible,
              textInputAction: TextInputAction.done,
              style: TextStyle(color: colors.textPrimary),
              decoration: _inputDecoration('Confirm Password', colors, accent)
                  .copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _confirmPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => setState(
                      () => _confirmPasswordVisible = !_confirmPasswordVisible),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            _buildButton(
              text: 'Reset Password',
              accent: accent,
              isLoading: state is AuthLoading,
              onPressed: () {
                if (_resetFormKey.currentState!.validate()) {
                  if (_resetToken != null) {
                    context.read<AuthBloc>().add(
                      ResetPasswordRequested(
                        resetToken: _resetToken!,
                        newPassword: _passwordController.text,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared Widgets ──

  InputDecoration _inputDecoration(
    String hintText,
    AtlasColors colors,
    Color accent,
  ) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: colors.textSecondary),
      filled: true,
      fillColor: colors.inputFill,
      counterStyle: TextStyle(color: colors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      errorStyle: const TextStyle(fontSize: 12),
    );
  }

  Widget _buildButton({
    required String text,
    required Color accent,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
