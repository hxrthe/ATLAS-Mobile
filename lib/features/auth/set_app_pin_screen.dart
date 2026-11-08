import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/app_lock_service.dart';
import '../../core/theme/app_theme.dart';
import 'login_screen.dart';

enum _PinStep { current, create, confirm }

/// One-time / change flow for the local 6-digit device PIN (not account login).
/// Matches [AppLockScreen] keypad + filled pin-circle UX.
class SetAppPinScreen extends StatefulWidget {
  const SetAppPinScreen({
    super.key,
    required this.onComplete,
    this.title = 'Set app PIN',
    this.subtitle =
        'This PIN unlocks ATLAS on this phone after idle or when you return. '
        'It does not replace your account password.',
    this.requireCurrentPin = false,
  });

  final VoidCallback onComplete;
  final String title;
  final String subtitle;
  final bool requireCurrentPin;

  @override
  State<SetAppPinScreen> createState() => _SetAppPinScreenState();
}

class _SetAppPinScreenState extends State<SetAppPinScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF8E1C1B);

  late _PinStep _step;
  String _entry = '';
  String? _createdPin;
  String? _verifiedCurrentPin;
  String? _error;
  bool _busy = false;
  bool _success = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _step = widget.requireCurrentPin ? _PinStep.current : _PinStep.create;
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
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String get _stepLabel {
    switch (_step) {
      case _PinStep.current:
        return 'Current PIN';
      case _PinStep.create:
        return widget.requireCurrentPin ? 'Create new PIN' : 'Create PIN';
      case _PinStep.confirm:
        return 'Confirm PIN';
    }
  }

  String get _stepHint {
    switch (_step) {
      case _PinStep.current:
        return 'Enter your current ${AppLockService.pinLength}-digit PIN';
      case _PinStep.create:
        return 'Choose a ${AppLockService.pinLength}-digit PIN for this phone';
      case _PinStep.confirm:
        return 'Enter the same PIN again to confirm';
    }
  }

  /// Right sprite = peeking (idle / success). Left sprite = covering eyes (typing).
  bool get _showPeeking => _success || _entry.isEmpty;

  static const _peekabooAsset =
      'assets/images/Pixel Knight Peekaboo Duo.png';
  static const _peekabooHeight = 148.0;

  Future<void> _shakeError(String message) async {
    HapticFeedback.heavyImpact();
    setState(() {
      _error = message;
      _entry = '';
      _busy = false;
    });
    await _shakeController.forward(from: 0);
  }

  /// Returns an error message when [pin] fails create-step rules; otherwise null.
  String? _validateNewPin(String pin) {
    if (pin.length != AppLockService.pinLength) {
      return 'Enter a ${AppLockService.pinLength}-digit PIN.';
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN must contain digits only.';
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) {
      return 'PIN cannot be the same digit repeated.';
    }
    if (_isSequentialDigits(pin)) {
      return 'PIN cannot be a simple sequence like 123456.';
    }
    if (_verifiedCurrentPin != null && pin == _verifiedCurrentPin) {
      return 'New PIN must be different from your current PIN.';
    }
    return null;
  }

  bool _isSequentialDigits(String pin) {
    var ascending = true;
    var descending = true;
    for (var i = 1; i < pin.length; i++) {
      final prev = int.parse(pin[i - 1]);
      final curr = int.parse(pin[i]);
      if (curr != (prev + 1) % 10) ascending = false;
      if (curr != (prev + 9) % 10) descending = false;
    }
    return ascending || descending;
  }

  Future<void> _onDigit(String digit) async {
    if (_busy || _success || _entry.length >= AppLockService.pinLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == AppLockService.pinLength) {
      await _onPinComplete(_entry);
    }
  }

  void _onBackspace() {
    if (_busy || _success || _entry.isEmpty) return;
    setState(() {
      _entry = _entry.substring(0, _entry.length - 1);
      _error = null;
    });
  }

  Future<void> _onPinComplete(String pin) async {
    setState(() => _busy = true);

    switch (_step) {
      case _PinStep.current:
        await _handleCurrentPin(pin);
      case _PinStep.create:
        await _handleCreatePin(pin);
      case _PinStep.confirm:
        await _handleConfirmPin(pin);
    }
  }

  Future<void> _handleCurrentPin(String pin) async {
    final lock = AppLockService.instance;
    final result = await lock.verifyPin(pin, unlockOnSuccess: false);
    if (!mounted) return;

    switch (result) {
      case PinVerifyResult.ok:
        setState(() {
          _verifiedCurrentPin = pin;
          _step = _PinStep.create;
          _entry = '';
          _error = null;
          _busy = false;
        });
      case PinVerifyResult.lockedOut:
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      case PinVerifyResult.wrong:
        final left = lock.attemptsRemaining;
        await _shakeError(
          left > 0
              ? 'Incorrect PIN. $left attempt${left == 1 ? '' : 's'} left.'
              : 'Incorrect PIN.',
        );
      case PinVerifyResult.invalidFormat:
      case PinVerifyResult.notSet:
        await _shakeError(
          'Enter your ${AppLockService.pinLength}-digit PIN.',
        );
    }
  }

  Future<void> _handleCreatePin(String pin) async {
    final validationError = _validateNewPin(pin);
    if (validationError != null) {
      await _shakeError(validationError);
      return;
    }
    if (!mounted) return;
    setState(() {
      _createdPin = pin;
      _step = _PinStep.confirm;
      _entry = '';
      _error = null;
      _busy = false;
    });
  }

  Future<void> _handleConfirmPin(String pin) async {
    if (_createdPin == null) {
      setState(() {
        _step = _PinStep.create;
        _entry = '';
        _busy = false;
        _error = 'Create a PIN first.';
      });
      return;
    }

    if (pin != _createdPin) {
      await _shakeError('PINs do not match. Try again.');
      setState(() {
        _step = _PinStep.create;
        _createdPin = null;
      });
      return;
    }

    final validationError = _validateNewPin(pin);
    if (validationError != null) {
      await _shakeError(validationError);
      setState(() {
        _step = _PinStep.create;
        _createdPin = null;
      });
      return;
    }

    try {
      await AppLockService.instance.setPin(pin);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _success = true;
        _busy = false;
        _error = null;
        _entry = pin;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.requireCurrentPin
                ? 'App PIN updated successfully.'
                : 'App PIN created successfully.',
          ),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      widget.onComplete();
    } catch (_) {
      if (!mounted) return;
      await _shakeError('Could not save PIN. Please try again.');
      setState(() {
        _step = _PinStep.create;
        _createdPin = null;
      });
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
        title: Text(widget.title),
        automaticallyImplyLeading: widget.requireCurrentPin,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _peekabooKnight(coveringEyes: !_showPeeking),
                    const SizedBox(height: 12),
                    Text(
                      _success ? 'PIN ready' : _stepLabel,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _success
                          ? 'Your device unlock PIN is set.'
                          : _stepHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        height: 1.35,
                        fontSize: 14,
                      ),
                    ),
                    if (!_success) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary.withValues(alpha: 0.9),
                          height: 1.35,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
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
                        children: List.generate(AppLockService.pinLength, (i) {
                          final filled = i < _entry.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? (_success
                                      ? const Color(0xFF2E7D32)
                                      : colors.primary)
                                  : Colors.transparent,
                              border: Border.all(
                                color: _success
                                    ? const Color(0xFF2E7D32)
                                    : colors.primary,
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
              if (!_success) _keypad(colors),
            ],
          ),
        ),
      ),
    );
  }

  /// Duo sprite sheet: left = covering eyes, right = peeking.
  Widget _peekabooKnight({required bool coveringEyes}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: SizedBox(
        key: ValueKey(coveringEyes),
        height: _peekabooHeight,
        // Square frame showing exactly one half of the 2:1 sheet.
        width: _peekabooHeight,
        child: ClipRect(
          child: Align(
            alignment: coveringEyes
                ? Alignment.centerLeft
                : Alignment.centerRight,
            widthFactor: 0.5,
            child: Image.asset(
              _peekabooAsset,
              height: _peekabooHeight,
              fit: BoxFit.fitHeight,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
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
              const SizedBox(width: 72, height: 56),
              _keyButton(colors, label: '0'),
              _keyButton(colors, label: '⌫', isBack: true),
            ],
          ),
        ),
      ],
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
