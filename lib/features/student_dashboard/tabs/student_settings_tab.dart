import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/login_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/auth_repository.dart';
import 'package:atlas_mobile/main.dart'; // Make sure this matches your main.dart import!

class StudentSettingsTab extends StatelessWidget {
  final String userName;

  const StudentSettingsTab({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final iconBgColor = isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFF4F6F9);

    return SafeArea(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        children: [
          Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 32),

          Center(
            child: Column(
              children: [
                const CircleAvatar(radius: 50, backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=33')),
                const SizedBox(height: 16),
                Text(userName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                Text('Student Account', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
              ],
            ),
          ),

          const SizedBox(height: 32),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.15), width: 1.5),
                ),
                child: Column(
                  children: [
                    // FIXED: Now correctly passing an Icon and a Title string to match the parameters
                    _buildSettingsTile(context, Icons.person_outline, 'Account Details', textColor, iconBgColor),
                    Divider(height: 1, indent: 56, color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),

                    ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeNotifier,
                        builder: (context, currentMode, child) {
                          final isCurrentlyDark = currentMode == ThemeMode.dark || (currentMode == ThemeMode.system && isDark);

                          return SwitchListTile(
                            activeColor: const Color(0xFF8B1515),
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)),
                              child: Icon(isCurrentlyDark ? Icons.dark_mode : Icons.light_mode, color: textColor, size: 20),
                            ),
                            title: Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textColor)),
                            value: isCurrentlyDark,
                            onChanged: (value) async {
                              themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('theme_mode', value ? 'dark' : 'light');
                            },
                          );
                        }
                    ),

                    Divider(height: 1, indent: 56, color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),

                    // FIXED: Corrected this layout row as well
                    _buildSettingsTile(context, Icons.help_outline, 'Help & Support', textColor, iconBgColor),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => BlocProvider(
                    create: (context) => AuthBloc(authRepository: AuthRepository()),
                    child: LoginScreen(),
                  ),
                ),
                    (Route<dynamic> route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.red.shade900.withOpacity(0.2) : const Color(0xFFFEF2F2),
              foregroundColor: isDark ? Colors.red.shade300 : Colors.red.shade700,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Log Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, Color textColor, Color iconBgColor) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: textColor, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textColor)),
      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
      onTap: () {},
    );
  }
}