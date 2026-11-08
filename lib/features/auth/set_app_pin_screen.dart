import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/app_lock_service.dart';
import '../../core/theme/app_theme.dart';
import 'login_screen.dart';

/// One-time / change flow for the local 6-digit device PIN (not account login).
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

class _SetAppPinScreenState extends State<SetAppPinScreen> {
  static const _primary = Color(0xFF8E1C1B);

  final _currentController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lock = AppLockService.instance;
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    setState(() => _error = null);

    if (widget.requireCurrentPin) {
      final current = _currentController.text.trim();
      final result = await lock.verifyPin(current, unlockOnSuccess: false);
      if (result == PinVerifyResult.lockedOut) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }
      if (result != PinVerifyResult.ok) {
        setState(() => _error = 'Current PIN is incorrect.');
        return;
      }
    }

    if (pin.length != AppLockService.pinLength ||
        !RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() => _error = 'Enter a ${AppLockService.pinLength}-digit PIN.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match.');
      return;
    }

    setState(() => _saving = true);
    try {
      await lock.setPin(pin);
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save PIN. Please try again.';
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
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.subtitle,
              style: TextStyle(
                color: colors.textSecondary,
                height: 1.45,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 28),
            if (widget.requireCurrentPin) ...[
              _pinField(
                colors,
                controller: _currentController,
                label: 'Current PIN',
                autofocus: true,
              ),
              const SizedBox(height: 16),
            ],
            _pinField(
              colors,
              controller: _pinController,
              label: 'New PIN',
              autofocus: !widget.requireCurrentPin,
            ),
            const SizedBox(height: 16),
            _pinField(
              colors,
              controller: _confirmController,
              label: 'Confirm PIN',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save PIN',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinField(
    AtlasColors colors, {
    required TextEditingController controller,
    required String label,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: AppLockService.pinLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}
