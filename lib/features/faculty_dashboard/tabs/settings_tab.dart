import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // <-- This gives you context.read()

import '../../auth/login_screen.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/auth_repository.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'ACCOUNT SETTINGS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF8391A1), letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
            ),
            title: Text('Dr. Hearty Delacion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('Faculty Instructor'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy & Security'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              // Show the Confirmation Dialog
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text(
                        'Log Out',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B1515))
                    ),
                    content: const Text('Are you sure you want to securely log out of the ATLAS portal?'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext), // Cancel
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext); // Close the dialog first

                          // Execute the logout sequence
                          await context.read<AuthRepository>().logout();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BlocProvider(
                                  create: (context) => AuthBloc(
                                    authRepository: context.read<AuthRepository>(),
                                  ),
                                  child: const LoginScreen(),
                                ),
                              ),
                                  (route) => false,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B1515),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Log Out'),
                      ),
                    ],
                  );
                },
              );
            },
            icon: const Icon(Icons.logout),
            label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF8B1515),
              side: const BorderSide(color: Color(0xFF8B1515), width: 2),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}