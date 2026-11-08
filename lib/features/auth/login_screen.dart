import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/app_lock_service.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../faculty_dashboard/faculty_dashboard_screen.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import 'forgot_password_screen.dart';
import 'set_app_pin_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool autoLogout;
  const LoginScreen({super.key, this.autoLogout = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final ScrollController _cardScroll = ScrollController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final AnimationController _intro;

  bool _isPasswordVisible = false;
  bool _logoutMessageShown = false;
  bool _prefsReady = false;

  static const _prefsGetStartedKey = 'login_get_started_seen';
  static const _primary = Color(0xFF8E1C1B);
  static const _leaf = Color(0xFFAA2423);
  static const _radius = 12.0; // web rounded-square (not pill)

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _emailFocus.addListener(_onFieldFocusChange);
    _passwordFocus.addListener(_onFieldFocusChange);
    ApiClient.loginScreenOpened();
    _bootstrap();

    if (widget.autoLogout && !_logoutMessageShown) {
      _logoutMessageShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You have been logged out due to inactivity. Please login again to continue.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: _primary,
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logout_type');
    final seen = prefs.getBool(_prefsGetStartedKey) ?? false;

    // Stop app-owned credential prefill; phone password managers may still suggest.
    await _secureStorage.delete(key: 'saved_email');
    await _secureStorage.delete(key: 'saved_password');
    if (!mounted) return;

    setState(() => _prefsReady = true);

    // Returning users (or auto-logout): skip Get Started → login.
    if (seen || widget.autoLogout) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) _intro.forward();
    }
  }

  Future<void> _onGetStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsGetStartedKey, true);
    if (!mounted) return;
    _intro.forward();
  }

  void _dismissToSplash() {
    if (_intro.value > 0.05) {
      FocusScope.of(context).unfocus();
      _intro.reverse();
    }
  }

  void _onFieldFocusChange() {
    if (!mounted) return;
    // Rebuild only so the dismiss-to-splash hit target can ignore while typing.
    setState(() {});
  }

  void _handleGoogleSignIn() {
    context.read<AuthBloc>().add(const GoogleLoginRequested());
  }

  Future<void> _enterAppAfterLogin() async {
    await AppLockService.instance.load();
    if (!mounted) return;
    if (!AppLockService.instance.hasPin) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (pinContext) => SetAppPinScreen(
            onComplete: () {
              Navigator.of(pinContext).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const FacultyDashboardScreen(),
                ),
              );
            },
          ),
        ),
      );
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const FacultyDashboardScreen()),
    );
  }

  @override
  void dispose() {
    ApiClient.loginScreenClosed();
    _emailFocus.removeListener(_onFieldFocusChange);
    _passwordFocus.removeListener(_onFieldFocusChange);
    _intro.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _cardScroll.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    required Color muted,
    required Color field,
    required Color fieldBorder,
    required Color hintColor,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: hintColor, fontSize: 14),
      prefixIcon: Icon(icon, color: muted, size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: field,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: _leaf.withValues(alpha: 0.85), width: 1.4),
      ),
    );
  }

  Widget _logo({double? width, double? height, required bool isDark}) {
    return SvgPicture.asset(
      'assets/images/atlas_mobile_logo.svg',
      width: width,
      height: height,
      fit: BoxFit.contain,
      // Dark mode: force the full logo red. Light: keep the SVG two-tone (MOBILE near black).
      colorFilter: isDark
          ? const ColorFilter.mode(Color(0xFFD0112B), BlendMode.srcIn)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // Real IME inset only — never invent padding that jumps the form (Instagram /
    // Material pattern: fixed chrome, keyboard overlays, form scrolls if needed).
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final fieldFocused =
        _emailFocus.hasFocus || _passwordFocus.hasFocus;
    final isDark = context.isDarkTheme;

    final colors = context.atlas;
    final bg = isDark ? colors.scaffold : const Color(0xFFFBF7F7);
    final card = isDark ? colors.card : Colors.white;
    final field = isDark ? colors.inputFill : const Color(0xFFF3F4F6);
    final fieldBorder = isDark ? colors.border : const Color(0xFFE5E7EB);
    final muted = isDark ? colors.textSecondary : const Color(0xFF6B7280);
    final text = isDark ? colors.textPrimary : const Color(0xFF111827);
    final accent = isDark ? colors.primary : _leaf;
    final hintColor =
        isDark ? const Color(0x47FFFFFF) : const Color(0xFF9CA3AF);
    final statusBarColor = isDark ? Colors.transparent : Colors.white;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: statusBarColor,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: card,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
          backgroundColor: bg,
          // Keyboard overlays; login card scrolls instead of resizing.
          resizeToAvoidBottomInset: false,
          body: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthSuccess) {
              TextInput.finishAutofillContext(shouldSave: true);
              unawaited(_enterAppAfterLogin());
            } else if (state is AuthFailure) {
              if (state.error.startsWith('GOOGLE_OAUTH_CONFIG:')) {
                final detail =
                    state.error.replaceFirst('GOOGLE_OAUTH_CONFIG: ', '');
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Google Sign-In setup needed'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        '$detail\n\n'
                        'This is not you tapping Cancel. Android reports "cancelled" when '
                        'the debug SHA-1 is missing from the Google Cloud Android OAuth client.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.error),
                    backgroundColor: Colors.red.shade800,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
          builder: (context, state) {
            final loadingSource =
                state is AuthLoading ? state.source : null;
            final emailLoading = loadingSource == AuthLoadingSource.email;
            final googleLoading = loadingSource == AuthLoadingSource.google;
            final isBusy = state is AuthLoading;

            return AnimatedBuilder(
              animation: _intro,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_intro.value);

                // Splash → login: same logo shrinks + rises; card fills 4/5.
                final cardOpacity = t;
                final cardDy = (1 - t) * size.height * 0.25;
                final cardH = size.height * 0.8;
                final topBandH = size.height - cardH;
                final getStartedOpacity =
                    (1.0 - t * 2.2).clamp(0.0, 1.0);

                // One continuous logo: splash (wide, center) → top above card.
                const logoAspect = 1920 / 1080;
                final splashLogoW = size.width * 0.92;
                final loginLogoW = size.width * 0.52;
                final logoW =
                    splashLogoW + (loginLogoW - splashLogoW) * t;
                final logoH = logoW / logoAspect;
                final splashLogoTop =
                    (size.height - logoH) * 0.38 - pad.bottom * 0.1;
                final loginLogoTop =
                    pad.top + ((topBandH - pad.top) - logoH) / 2;
                final logoTop =
                    splashLogoTop + (loginLogoTop - splashLogoTop) * t;
                final logoLeft = (size.width - logoW) / 2;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: isDark
                              ? const Alignment(-0.2, -0.35)
                              : const Alignment(-0.15, -0.4),
                          radius: isDark ? 1.15 : 1.2,
                          colors: isDark
                              ? const [
                                  Color(0xFF2A2223),
                                  Color(0xFF212425),
                                  Color(0xFF1D2021),
                                ]
                              : const [
                                  Color(0xFFF8D4D3),
                                  Color(0xFFFFF5F5),
                                  Color(0xFFFBF7F7),
                                ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _WebGridPainter(progress: t, isDark: isDark),
                    ),

                    // Status-bar strip (white in light so clock stays readable)
                    if (!isDark)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: pad.top,
                        child: const ColoredBox(color: Colors.white),
                      ),

                    // Tap above the card → back to splash + Get Started
                    if (t > 0.2 && !fieldFocused)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: topBandH,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _dismissToSplash,
                        ),
                      ),

                    // Get Started (splash only)
                    if (_prefsReady && getStartedOpacity > 0)
                      Positioned(
                        left: 28,
                        right: 28,
                        bottom: 36 + pad.bottom,
                        child: Opacity(
                          opacity: getStartedOpacity,
                          child: IgnorePointer(
                            ignoring: t > 0.15,
                            child: SizedBox(
                              height: 54,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(_radius),
                                  gradient: const LinearGradient(
                                    colors: [_primary, _leaf],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _primary.withValues(alpha: 0.28),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _onGetStarted,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(_radius),
                                    ),
                                  ),
                                  child: const Text(
                                    'Get Started',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Login card — fixed shell; title pinned; keyboard overlays.
                    if (t > 0.05)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: cardH,
                        // Avoid Opacity/Transform once settled — they can drop IME focus.
                        child: () {
                          final sheet = Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.55 : 0.22,
                                    ),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                    offset: const Offset(0, -14),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.35 : 0.10,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, -4),
                                  ),
                                ],
                              ),
                              child: Material(
                              color: card,
                              elevation: 0,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SafeArea(
                                top: false,
                                // Keep home-indicator padding when IME is closed;
                                // when open, only the scroll body clears the keys.
                                bottom: keyboard <= 0,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Pinned — never scrolls or jumps with IME.
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        28,
                                        36,
                                        28,
                                        0,
                                      ),
                                      child: Text(
                                        'Sign In',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: text,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        controller: _cardScroll,
                                        padding: EdgeInsets.fromLTRB(
                                          28,
                                          36,
                                          28,
                                          24 +
                                              (keyboard > 0
                                                  ? keyboard
                                                  : pad.bottom),
                                        ),
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        child: AutofillGroup(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                      Text(
                                        'EMAIL',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: muted,
                                          letterSpacing: 0.7,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _usernameController,
                                        focusNode: _emailFocus,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autofillHints: const [
                                          AutofillHints.email,
                                          AutofillHints.username,
                                        ],
                                        textInputAction: TextInputAction.next,
                                        onSubmitted: (_) =>
                                            _passwordFocus.requestFocus(),
                                        // Keep labels readable above the field;
                                        // do not auto-jump the whole form.
                                        scrollPadding:
                                            const EdgeInsets.only(bottom: 24),
                                        style: TextStyle(
                                            color: text, fontSize: 14.5),
                                        cursorColor: _leaf,
                                        decoration: _fieldDecoration(
                                          hint: 'you@institution.edu',
                                          icon: Icons.email_outlined,
                                          muted: muted,
                                          field: field,
                                          fieldBorder: fieldBorder,
                                          hintColor: hintColor,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      Text(
                                        'PASSWORD',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: muted,
                                          letterSpacing: 0.7,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _passwordController,
                                        focusNode: _passwordFocus,
                                        obscureText: !_isPasswordVisible,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        textInputAction: TextInputAction.done,
                                        scrollPadding:
                                            const EdgeInsets.only(bottom: 24),
                                        style: TextStyle(
                                            color: text, fontSize: 14.5),
                                        cursorColor: _leaf,
                                        onSubmitted: (_) {
                                          if (!isBusy) {
                                            context.read<AuthBloc>().add(
                                                  LoginRequested(
                                                    email: _usernameController
                                                        .text,
                                                    password:
                                                        _passwordController
                                                            .text,
                                                  ),
                                                );
                                          }
                                        },
                                        decoration: _fieldDecoration(
                                          hint: '••••••••••••',
                                          icon: Icons.lock_outline,
                                          muted: muted,
                                          field: field,
                                          fieldBorder: fieldBorder,
                                          hintColor: hintColor,
                                          suffix: IconButton(
                                            icon: Icon(
                                              _isPasswordVisible
                                                  ? Icons
                                                      .visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              color: muted,
                                            ),
                                            onPressed: () => setState(
                                              () => _isPasswordVisible =
                                                  !_isPasswordVisible,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ForgotPasswordScreen(
                                                  initialEmail:
                                                      _usernameController.text
                                                          .trim(),
                                                ),
                                              ),
                                            );
                                          },
                                          child: Text(
                                            'Forgot password?',
                                            style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      SizedBox(
                                        height: 52,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(_radius),
                                            gradient: const LinearGradient(
                                              colors: [_primary, _leaf],
                                            ),
                                          ),
                                          child: ElevatedButton(
                                            onPressed: isBusy
                                                ? null
                                                : () {
                                                    context
                                                        .read<AuthBloc>()
                                                        .add(
                                                          LoginRequested(
                                                            email:
                                                                _usernameController
                                                                    .text,
                                                            password:
                                                                _passwordController
                                                                    .text,
                                                          ),
                                                        );
                                                  },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              disabledBackgroundColor:
                                                  Colors.transparent,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        _radius),
                                              ),
                                            ),
                                            child: emailLoading
                                                ? const SizedBox(
                                                    height: 22,
                                                    width: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.4,
                                                    ),
                                                  )
                                                : const Text(
                                                    'LOGIN',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Divider(color: fieldBorder),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            child: Text(
                                              'OR',
                                              style: TextStyle(
                                                color: muted,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Divider(color: fieldBorder),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      SizedBox(
                                        height: 52,
                                        child: OutlinedButton(
                                          onPressed: isBusy
                                              ? null
                                              : _handleGoogleSignIn,
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color: fieldBorder,
                                            ),
                                            foregroundColor: text,
                                            backgroundColor: field,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      _radius),
                                            ),
                                          ),
                                          child: googleLoading
                                              ? const SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.4,
                                                    color: _leaf,
                                                  ),
                                                )
                                              : Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Image.asset(
                                                      'assets/images/google_g_logo.png',
                                                      width: 20,
                                                      height: 20,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    const Text(
                                                      'Continue with Google',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          if (t >= 0.999) return sheet;
                          return Opacity(
                            opacity: cardOpacity,
                            child: Transform.translate(
                              offset: Offset(0, cardDy),
                              child: sheet,
                            ),
                          );
                        }(),
                      ),

                    // Same logo: splash center → shrinks into top band above card
                    Positioned(
                      left: logoLeft,
                      top: logoTop.clamp(pad.top, size.height),
                      width: logoW,
                      height: logoH,
                      child: IgnorePointer(
                        child: _logo(
                          width: logoW,
                          height: logoH,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Soft grid for the ATLAS auth shell (light / dark).
class _WebGridPainter extends CustomPainter {
  _WebGridPainter({required this.progress, required this.isDark});
  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.035 + 0.015 * progress)
          : const Color(0xFF8E1C1B).withValues(alpha: 0.045 + 0.02 * progress)
      ..strokeWidth = 1;

    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        center: Alignment(0.7, isDark ? -0.6 : -0.55),
        radius: 1.05,
        colors: [
          const Color(0xFFD0112B).withValues(alpha: isDark ? 0.16 : 0.10),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _WebGridPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}
