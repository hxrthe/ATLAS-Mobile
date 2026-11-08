import 'package:flutter/material.dart';

import '../../core/auth/app_lock_service.dart';
import '../../core/auth/token_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_loading_view.dart';
import '../faculty_dashboard/faculty_dashboard_screen.dart';
import 'app_lock_screen.dart';
import 'login_screen.dart';
import 'set_app_pin_screen.dart';

/// Cold-start gate: login, set PIN, or unlock an existing session.
class AuthBootstrap extends StatefulWidget {
  const AuthBootstrap({super.key});

  @override
  State<AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<AuthBootstrap> {
  bool _loading = true;
  Widget? _home;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    await AppLockService.instance.load();
    final hasSession = await TokenStore.hasSession();
    if (!mounted) return;

    if (!hasSession) {
      setState(() {
        _home = const LoginScreen();
        _loading = false;
      });
      return;
    }

    final lock = AppLockService.instance;
    if (!lock.hasPin) {
      setState(() {
        _home = SetAppPinScreen(
          onComplete: () {
            if (!mounted) return;
            setState(() => _home = const FacultyDashboardScreen());
          },
        );
        _loading = false;
      });
      return;
    }

    lock.lock();
    setState(() {
      _home = ColdStartLockGate(
        child: const FacultyDashboardScreen(),
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _home == null) {
      final colors = context.atlas;
      return Scaffold(
        backgroundColor: colors.scaffold,
        body: const AtlasLoadingView(layout: AtlasLoadingLayout.list),
      );
    }
    return _home!;
  }
}
