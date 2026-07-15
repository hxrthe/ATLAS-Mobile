import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart'; // <--- Your centralized theme engine
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// STRICT RELATIVE IMPORTS
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/login_screen.dart';

// 1. Create a global broadcaster to instantly swap themes
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  // 2. Ensure Flutter is ready to talk to device memory before booting
  WidgetsFlutterBinding.ensureInitialized();

  // 3. Check memory to see if the user saved a theme preference previously
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode');
  if (savedTheme == 'light') themeNotifier.value = ThemeMode.light;
  if (savedTheme == 'dark') themeNotifier.value = ThemeMode.dark;


  await Supabase.initialize(
    url: 'https://ycsafjkouarqpzanxelz.supabase.co',
    anonKey: 'Ysb_publishable_4TOcTvAhnhIrbMXr5Rt2bA_BzrF0NMb',
  );

  runApp(const AtlasMobileApp());
}

class AtlasMobileApp extends StatelessWidget {
  const AtlasMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => AuthRepository(),

      // 4. Wrap MaterialApp so it listens to the broadcaster
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (_, ThemeMode currentMode, __) {

          return MaterialApp(
            title: 'ATLAS Mobile',
            debugShowCheckedModeBanner: false,
            themeMode: currentMode, // <--- Reacts instantly to the toggle!

            // 5. INJECT YOUR NEW THEME ENGINE HERE
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,

            home: BlocProvider(
              create: (context) => AuthBloc(
                authRepository: context.read<AuthRepository>(),
              ),
              child: LoginScreen(), // Remove 'const' if your LoginScreen throws an error here
            ),
          );

        },
      ),
    );
  }
}