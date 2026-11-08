import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// JWT access/refresh in platform secure storage (not SharedPreferences).
class TokenStore {
  TokenStore._();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static Future<void>? _migrateTask;

  static Future<void> _migrateFromPrefsIfNeeded() async {
    final existing = _migrateTask;
    if (existing != null) {
      await existing;
      return;
    }
    final task = _doMigrate();
    _migrateTask = task;
    try {
      await task;
    } finally {
      _migrateTask = null;
    }
  }

  static Future<void> _doMigrate() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyAccess = prefs.getString(_accessKey);
    final legacyRefresh = prefs.getString(_refreshKey);
    if ((legacyAccess == null || legacyAccess.isEmpty) &&
        (legacyRefresh == null || legacyRefresh.isEmpty)) {
      return;
    }

    final secureAccess = await _secure.read(key: _accessKey);
    final secureRefresh = await _secure.read(key: _refreshKey);

    if ((secureAccess == null || secureAccess.isEmpty) &&
        legacyAccess != null &&
        legacyAccess.isNotEmpty) {
      await _secure.write(key: _accessKey, value: legacyAccess);
    }
    if ((secureRefresh == null || secureRefresh.isEmpty) &&
        legacyRefresh != null &&
        legacyRefresh.isNotEmpty) {
      await _secure.write(key: _refreshKey, value: legacyRefresh);
    }

    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  static Future<String?> readAccess() async {
    await _migrateFromPrefsIfNeeded();
    return _secure.read(key: _accessKey);
  }

  static Future<String?> readRefresh() async {
    await _migrateFromPrefsIfNeeded();
    return _secure.read(key: _refreshKey);
  }

  static Future<bool> hasSession() async {
    final access = await readAccess();
    return access != null && access.isNotEmpty;
  }

  static Future<void> write({
    required String access,
    String? refresh,
  }) async {
    await _migrateFromPrefsIfNeeded();
    await _secure.write(key: _accessKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      await _secure.write(key: _refreshKey, value: refresh);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  static Future<void> writeAccess(String access) async {
    await _migrateFromPrefsIfNeeded();
    await _secure.write(key: _accessKey, value: access);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
  }

  static Future<void> clear() async {
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}
