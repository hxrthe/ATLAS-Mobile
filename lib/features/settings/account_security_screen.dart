import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/app_lock_service.dart';
import '../../core/auth/token_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_loading_view.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/forgot_password_screen.dart';
import '../auth/login_screen.dart';
import '../auth/set_app_pin_screen.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String _userName = '';
  String _userEmail = '';
  String _userRole = '';
  String? _userPhotoUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear any leftover app-owned credential prefill keys.
    await _secureStorage.delete(key: 'saved_email');
    await _secureStorage.delete(key: 'saved_password');
    await AppLockService.instance.load();
    await AppLockService.instance.refreshBiometricAvailability();

    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'User';
        _userEmail = prefs.getString('user_email') ?? '';
        _userRole = prefs.getString('user_role') ?? 'faculty';
        _userPhotoUrl = prefs.getString('user_photo_url');
        _isLoading = false;
      });
    }
  }

  Future<void> _openChangePin() async {
    final lock = AppLockService.instance;
    if (!lock.hasPin) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (pinContext) => SetAppPinScreen(
            title: 'Set app lock',
            onComplete: () {
              Navigator.of(pinContext).pop();
              if (mounted) setState(() {});
            },
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (pinContext) => SetAppPinScreen(
          title: 'Change app lock',
          subtitle:
              'Enter your current PIN, then choose a new 6-digit PIN. '
              'App lock stays on this phone for any account you use here.',
          requireCurrentPin: true,
          onComplete: () {
            Navigator.of(pinContext).pop();
            if (mounted) setState(() {});
          },
        ),
      ),
    );

    final stillSignedIn = await TokenStore.hasSession();
    if (!mounted) return;
    if (!stillSignedIn) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    final lock = AppLockService.instance;

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
          'Account & Security',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const AtlasLoadingView(layout: AtlasLoadingLayout.list)
          : ListenableBuilder(
              listenable: lock,
              builder: (context, _) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIEW PROFILE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            UserAvatar(
                              photoUrl: _userPhotoUrl,
                              name: _userName,
                              radius: 30,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _userEmail,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (_userRole.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _userRole.toUpperCase(),
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'DEVICE UNLOCK',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Unlocks this phone after idle or when you return. '
                        'It does not replace your account password.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (lock.biometricAvailable)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border),
                          ),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(
                              Icons.fingerprint,
                              color: colors.primary,
                            ),
                            title: Text(
                              'Unlock with biometrics',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Face or fingerprint when available',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            value: lock.biometricEnabled,
                            activeThumbColor: colors.primary,
                            onChanged: lock.hasPin
                                ? (value) async {
                                    await lock.setBiometricEnabled(value);
                                  }
                                : null,
                          ),
                        ),
                      _buildSettingTile(
                        colors,
                        icon: Icons.lock_outline,
                        title: lock.hasPin ? 'Change app lock' : 'Set app lock',
                        subtitle: lock.hasPin
                            ? 'Update the unlock PIN for this phone'
                            : 'Required to unlock after idle or background',
                        onTap: _openChangePin,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'LOGIN PREFERENCES',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSettingTile(
                        colors,
                        icon: Icons.lock_reset,
                        title: 'Password Reset',
                        subtitle: 'Change your account password',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ForgotPasswordScreen(
                                initialEmail: _userEmail,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSettingTile(
    AtlasColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
