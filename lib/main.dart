import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_scale_controller.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_bootstrap.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/scanner/offline_save_alerts.dart';
import 'features/scanner/offline_save_bar.dart';
import 'features/scanner/offline_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  await fontScaleController.load();
  await OfflineSaveAlerts.start();
  OfflineSync.instance.start();
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
          listenable: Listenable.merge([
            themeController,
            fontScaleController,
          ]),
          builder: (context, _) {
            return MaterialApp(
              title: 'ATLAS Mobile',
              debugShowCheckedModeBanner: false,
              navigatorKey: ApiClient.navigatorKey,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeController.mode,
              builder: (context, child) {
                final dark = Theme.of(context).brightness == Brightness.dark;
                final scaffold = Theme.of(context).scaffoldBackgroundColor;
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(fontScaleController.scale)
                        .clamp(
                          minScaleFactor: FontScaleController.smallScale,
                          maxScaleFactor: FontScaleController.largeScale,
                        ),
                  ),
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness:
                          dark ? Brightness.light : Brightness.dark,
                      statusBarBrightness:
                          dark ? Brightness.dark : Brightness.light,
                      systemNavigationBarColor: scaffold,
                      systemNavigationBarIconBrightness:
                          dark ? Brightness.light : Brightness.dark,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        child ?? const SizedBox.shrink(),
                        const OfflineSaveNotice(),
                      ],
                    ),
                  ),
                );
              },
              home: const AuthBootstrap(),
            );
          },
        ),
      ),
    );
  }
}
