import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/font_scale_controller.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/atlas_pull_to_refresh.dart';
import '../../auth/login_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/auth_repository.dart';
import '../../scanner/offline_pack.dart';
import '../../scanner/offline_sync.dart';
import '../../settings/account_security_screen.dart';
import '../../settings/help_support_screen.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String _userName = 'Instructor';
  String _userRole = 'Faculty';
  String? _userPhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _syncFiles() async {
    final ok = await OfflinePack.runSync(() => OfflineSync.instance.flush());
    if (!mounted || ok) return;
    final offline = !await OfflinePack.probe();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          offline
              ? 'Connect to the internet, then try again.'
              : 'That did not finish. Try again in a moment.',
        ),
      ),
    );
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Instructor';
        _userRole = 'Faculty Instructor';
        _userPhotoUrl = prefs.getString('user_photo_url');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    return SafeArea(
      bottom: false,
      child: AtlasPullToRefresh(
        onRefresh: _loadUser,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
          children: [
            Text(
              'ACCOUNT SETTINGS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: UserAvatar(
                photoUrl: _userPhotoUrl,
                name: _userName,
                radius: 24,
              ),
              title: Text(_userName,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: colors.textPrimary)),
              subtitle: Text(_userRole,
                  style: TextStyle(color: colors.textSecondary)),
            ),
            ValueListenableBuilder<PackAttention>(
              valueListenable: OfflinePack.attention,
              builder: (context, attention, _) {
                if (!attention.needsAttention && !attention.busy) {
                  return const SizedBox.shrink();
                }
                final icon = attention.needsUpload && attention.needsDownload
                    ? Icons.sync_problem
                    : attention.needsUpload
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_download_outlined;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: colors.ambiguous),
                  title: Text(
                    attention.headline,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    attention.detail,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  trailing: attention.busy
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          tooltip: 'Update now',
                          onPressed: _syncFiles,
                          icon: const Icon(Icons.sync),
                        ),
                  onTap: attention.busy ? null : _syncFiles,
                );
              },
            ),
            Divider(height: 32, color: colors.divider),
            Text(
              'APPEARANCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: themeController,
              builder: (context, _) {
                final dark = themeController.mode == ThemeMode.dark;
                return SwitchListTile(
                  secondary: Icon(
                    dark ? Icons.dark_mode : Icons.light_mode,
                    color: colors.textSecondary,
                  ),
                  title: Text('Dark mode',
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text(
                    dark
                        ? 'Using results-style dark palette'
                        : 'Using light campus palette',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  value: dark,
                  onChanged: (v) => themeController
                      .setMode(v ? ThemeMode.dark : ThemeMode.light),
                );
              },
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: fontScaleController,
              builder: (context, _) {
                final scale = fontScaleController.scale;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.text_fields,
                        color: colors.textSecondary,
                      ),
                      title: Text(
                        'Text size',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      subtitle: Text(
                        'Larger text for easier reading',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in const [
                            (FontScaleController.defaultScale, 'Default'),
                            (FontScaleController.largeScale, 'Large'),
                            (
                              FontScaleController.extraLargeScale,
                              'Extra large'
                            ),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: scale == option.$1,
                              onSelected: (_) =>
                                  fontScaleController.setScale(option.$1),
                              selectedColor: colors.primary,
                              backgroundColor: colors.cardMuted,
                              labelStyle: TextStyle(
                                color: scale == option.$1
                                    ? colors.onPrimary
                                    : colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              side: BorderSide(
                                color: scale == option.$1
                                    ? colors.primary
                                    : colors.border,
                              ),
                              showCheckmark: false,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Divider(height: 32, color: colors.divider),
            ListTile(
              leading: Icon(Icons.lock_outline, color: colors.textSecondary),
              title: Text('Account & Security',
                  style: TextStyle(color: colors.textPrimary)),
              trailing: Icon(Icons.arrow_forward_ios,
                  size: 16, color: colors.textSecondary),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AccountSecurityScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.help_outline, color: colors.textSecondary),
              title: Text('Help & Support',
                  style: TextStyle(color: colors.textPrimary)),
              trailing: Icon(Icons.arrow_forward_ios,
                  size: 16, color: colors.textSecondary),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const HelpSupportScreen()),
                );
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext dialogContext) {
                    final dColors = dialogContext.atlas;
                    return AlertDialog(
                      backgroundColor: dColors.card,
                      title: Text('Log Out',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: dColors.primary)),
                      content: Text(
                        'Are you sure you want to securely log out of the ATLAS portal?',
                        style: TextStyle(color: dColors.textSecondary),
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text('Cancel',
                              style: TextStyle(
                                  color: dColors.textSecondary,
                                  fontWeight: FontWeight.bold)),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await context.read<AuthRepository>().logout();
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => BlocProvider(
                                    create: (context) => AuthBloc(
                                      authRepository:
                                          context.read<AuthRepository>(),
                                    ),
                                    child: const LoginScreen(),
                                  ),
                                ),
                                (route) => false,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: dColors.primary,
                            foregroundColor: dColors.onPrimary,
                          ),
                          child: const Text('Log Out'),
                        ),
                      ],
                    );
                  },
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Log Out',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.card,
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
