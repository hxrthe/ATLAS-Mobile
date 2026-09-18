import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  runApp(const AtlasMobileApp());
}

class AtlasMobileApp extends StatelessWidget {
  const AtlasMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => AuthRepository(),
      child: BlocProvider(
        create: (context) => AuthBloc(
          authRepository: context.read<AuthRepository>(),
        ),
        child: ListenableBuilder(
          listenable: themeController,
          builder: (context, _) {
            return MaterialApp(
              title: 'ATLAS Mobile',
              debugShowCheckedModeBanner: false,
              navigatorKey: ApiClient.navigatorKey,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeController.mode,
              home: const LoginScreen(),
            );
          },
        ),
      ),
    );
  }
}
