import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'token_store.dart';

/// Local device unlock only — never replaces account password/Google login.
class AppLockService extends ChangeNotifier {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const maxPinAttempts = 5;
  static const pinLength = 6;

  static const _pinHashKey = 'app_pin_hash';
  static const _pinSaltKey = 'app_pin_salt';
  static const _failCountKey = 'app_pin_fail_count';
  static const _biometricPrefKey = 'app_lock_biometric_enabled';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _locked = false;
  bool _ready = false;
  bool _hasPin = false;
  bool _biometricEnabled = true;
  bool _biometricAvailable = false;
  int _failCount = 0;

  bool get isLocked => _locked;
  bool get isReady => _ready;
  bool get hasPin => _hasPin;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  int get failCount => _failCount;
  int get attemptsRemaining => max(0, maxPinAttempts - _failCount);

  Future<void> load() async {
    final hash = await _secure.read(key: _pinHashKey);
    final salt = await _secure.read(key: _pinSaltKey);
    _hasPin = (hash != null && hash.isNotEmpty) && (salt != null && salt.isNotEmpty);

    final failRaw = await _secure.read(key: _failCountKey);
    _failCount = int.tryParse(failRaw ?? '') ?? 0;

    final prefs = await SharedPreferences.getInstance();
    _biometricEnabled = prefs.getBool(_biometricPrefKey) ?? true;
    _biometricAvailable = await _probeBiometrics();
    _ready = true;
    notifyListeners();
  }

  Future<bool> _probeBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshBiometricAvailability() async {
    _biometricAvailable = await _probeBiometrics();
    notifyListeners();
  }

  void lock() {
    if (_locked) return;
    _locked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    _biometricEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricPrefKey, enabled);
    notifyListeners();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  String _newSalt() {
    final rng = Random.secure();
    final values = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(values);
  }

  Future<void> setPin(String pin) async {
    if (!_isValidPin(pin)) {
      throw ArgumentError('PIN must be $pinLength digits.');
    }
    final salt = _newSalt();
    final hash = _hashPin(pin, salt);
    await _secure.write(key: _pinSaltKey, value: salt);
    await _secure.write(key: _pinHashKey, value: hash);
    await _secure.write(key: _failCountKey, value: '0');
    _hasPin = true;
    _failCount = 0;
    if (_biometricAvailable) {
      await setBiometricEnabled(true);
    }
    notifyListeners();
  }

  bool _isValidPin(String pin) =>
      pin.length == pinLength && RegExp(r'^\d+$').hasMatch(pin);

  /// Checks the local PIN. On the 5th failure, clears the session.
  Future<PinVerifyResult> verifyPin(
    String pin, {
    bool unlockOnSuccess = true,
  }) async {
    if (!_isValidPin(pin)) {
      return PinVerifyResult.invalidFormat;
    }
    final salt = await _secure.read(key: _pinSaltKey);
    final hash = await _secure.read(key: _pinHashKey);
    if (salt == null || hash == null) {
      return PinVerifyResult.notSet;
    }
    if (_hashPin(pin, salt) == hash) {
      _failCount = 0;
      await _secure.write(key: _failCountKey, value: '0');
      if (unlockOnSuccess) unlock();
      notifyListeners();
      return PinVerifyResult.ok;
    }

    _failCount += 1;
    await _secure.write(key: _failCountKey, value: '$_failCount');
    notifyListeners();
    if (_failCount >= maxPinAttempts) {
      await _lockoutClearSession();
      return PinVerifyResult.lockedOut;
    }
    return PinVerifyResult.wrong;
  }

  Future<void> _lockoutClearSession() async {
    _failCount = 0;
    await _secure.write(key: _failCountKey, value: '0');
    await TokenStore.clear();
    unlock();
    notifyListeners();
  }

  /// Returns true on success. Throws [BiometricAuthException] when the prompt
  /// cannot start so the lock screen can show a PIN fallback message.
  Future<bool> authenticateWithBiometrics({
    String reason = 'Unlock ATLAS',
  }) async {
    await refreshBiometricAvailability();
    if (!_biometricEnabled) return false;
    if (!_biometricAvailable) {
      throw BiometricAuthException('Biometrics unavailable — use your PIN');
    }
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) {
        _failCount = 0;
        await _secure.write(key: _failCountKey, value: '0');
        unlock();
        notifyListeners();
      }
      return ok;
    } on PlatformException catch (e, st) {
      debugPrint('Biometric authenticate failed: ${e.code} ${e.message}\n$st');
      // User dismissed the sheet — stay on PIN entry quietly.
      if (e.code == 'userCanceled' ||
          e.code == 'UserCanceled' ||
          e.code == 'auth_in_progress') {
        return false;
      }
      throw BiometricAuthException('Biometrics unavailable — use your PIN');
    } catch (e, st) {
      debugPrint('Biometric authenticate failed: $e\n$st');
      throw BiometricAuthException('Biometrics unavailable — use your PIN');
    }
  }
}

class BiometricAuthException implements Exception {
  BiometricAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum PinVerifyResult {
  ok,
  wrong,
  lockedOut,
  invalidFormat,
  notSet,
}
