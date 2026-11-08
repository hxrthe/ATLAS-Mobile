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

class _AppLockScreenState extends State<AppLockScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF8E1C1B);

  String _pin = '';
  String? _error;
  bool _busy = false;
  bool _biometricTried = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppLockService.instance.refreshBiometricAvailability();
      if (mounted) setState(() {});
      await _tryBiometric();
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _shakePinCircles() async {
    HapticFeedback.heavyImpact();
    await _shakeController.forward(from: 0);
  }

  Future<void> _tryBiometric() async {
    if (_biometricTried || _busy) return;
    final lock = AppLockService.instance;
    if (!lock.biometricEnabled || !lock.biometricAvailable) return;
    _biometricTried = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await lock.authenticateWithBiometrics(
        reason: 'Unlock ATLAS',
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) widget.onUnlocked();
    } on BiometricAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Biometrics unavailable — use your PIN';
      });
    }
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
        await _shakePinCircles();
      case PinVerifyResult.invalidFormat:
      case PinVerifyResult.notSet:
        setState(() {
          _busy = false;
          _pin = '';
          _error = 'Enter your ${AppLockService.pinLength}-digit PIN.';
        });
        await _shakePinCircles();
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
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      Image.asset(
                        'assets/images/Atlas Holding a Golden Padlock.png',
                        height: 168,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'ATLAS is locked',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.reason,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          height: 1.35,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: child,
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:
                              List.generate(AppLockService.pinLength, (i) {
                            final filled = i < _pin.length;
                            return Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: filled
                                    ? colors.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: colors.primary,
                                  width: 1.5,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      SizedBox(
                        height: 36,
                        child: _error == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                      ),
                      const Spacer(flex: 1),
                    ],
                  ),
                ),
                _keypad(colors, showBio: showBio),
                const SizedBox(height: 12),
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

  Widget _keypad(AtlasColors colors, {required bool showBio}) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        ...keys.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row
                  .map((key) => _keyButton(colors, label: key))
                  .toList(),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              showBio
                  ? _bioButton(colors)
                  : const SizedBox(width: 72, height: 56),
              _keyButton(colors, label: '0'),
              _keyButton(colors, label: '⌫', isBack: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bioButton(AtlasColors colors) {
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
                  _biometricTried = false;
                  _tryBiometric();
                },
          child: Icon(
            Icons.fingerprint,
            size: 28,
            color: colors.primary,
          ),
        ),
      ),
    );
  }

  Widget _keyButton(
    AtlasColors colors, {
    required String label,
    bool isBack = false,
  }) {
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
                    _onDigit(label);
                  }
                },
          child: Center(
            child: Text(
              label,
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
