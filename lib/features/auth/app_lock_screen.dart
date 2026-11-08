import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/app_lock_service.dart';
import '../../core/auth/token_store.dart';
import '../../core/theme/app_theme.dart';
import 'login_screen.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    required this.onUnlocked,
    this.reason = 'Enter your app PIN to continue',
  });

  final VoidCallback onUnlocked;
  final String reason;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  static const _primary = Color(0xFF8E1C1B);

  String _pin = '';
  String? _error;
  bool _busy = false;
  bool _biometricTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    if (_biometricTried || _busy) return;
    final lock = AppLockService.instance;
    if (!lock.biometricEnabled || !lock.biometricAvailable) return;
    _biometricTried = true;
    setState(() => _busy = true);
    final ok = await lock.authenticateWithBiometrics(
      reason: 'Unlock ATLAS',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onUnlocked();
  }

  Future<void> _onDigit(String digit) async {
    if (_busy || _pin.length >= AppLockService.pinLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == AppLockService.pinLength) {
      await _submitPin();
    }
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _submitPin() async {
    setState(() => _busy = true);
    final result = await AppLockService.instance.verifyPin(_pin);
    if (!mounted) return;

    switch (result) {
      case PinVerifyResult.ok:
        widget.onUnlocked();
        return;
      case PinVerifyResult.lockedOut:
        await _goToLoginAfterLockout();
        return;
      case PinVerifyResult.wrong:
        setState(() {
          _busy = false;
          _pin = '';
          final left = AppLockService.instance.attemptsRemaining;
          _error = left > 0
              ? 'Incorrect PIN. $left attempt${left == 1 ? '' : 's'} left.'
              : 'Incorrect PIN.';
        });
      case PinVerifyResult.invalidFormat:
      case PinVerifyResult.notSet:
        setState(() {
          _busy = false;
          _pin = '';
          _error = 'Enter your ${AppLockService.pinLength}-digit PIN.';
        });
    }
  }

  Future<void> _goToLoginAfterLockout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logout_type');
    await TokenStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(
          autoLogout: false,
        ),
      ),
      (_) => false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Too many incorrect PIN attempts. Sign in again with your account password.',
          ),
          backgroundColor: _primary,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('logout_type', 'intentional');
    await TokenStore.clear();
    AppLockService.instance.unlock();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    final lock = AppLockService.instance;
    final showBio = lock.biometricEnabled && lock.biometricAvailable;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.scaffold,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const Spacer(),
                Icon(Icons.lock_outline, size: 48, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  'ATLAS is locked',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(AppLockService.pinLength, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? colors.primary : Colors.transparent,
                        border: Border.all(color: colors.primary, width: 1.5),
                      ),
                    );
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (showBio)
                  TextButton.icon(
                    onPressed: _busy ? null : () {
                      _biometricTried = false;
                      _tryBiometric();
                    },
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use biometrics'),
                    style: TextButton.styleFrom(foregroundColor: colors.primary),
                  ),
                const Spacer(),
                _keypad(colors),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: Text(
                    'Sign out',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad(AtlasColors colors) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 56);
              }
              final isBack = key == '⌫';
              return SizedBox(
                width: 72,
                height: 56,
                child: Material(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            if (isBack) {
                              _onBackspace();
                            } else {
                              _onDigit(key);
                            }
                          },
                    child: Center(
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: isBack ? 22 : 24,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

/// Full-screen lock used at cold start; unlock goes to [onUnlocked] destination.
class ColdStartLockGate extends StatelessWidget {
  const ColdStartLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppLockScreen(
      onUnlocked: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => child),
        );
      },
    );
  }
}
