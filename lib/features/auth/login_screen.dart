import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:video_player/video_player.dart';
import '../student_dashboard/student_dashboard_screen.dart';

// STRICT RELATIVE IMPORTS
import '../faculty_dashboard/faculty_dashboard_screen.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'package:flutter/services.dart';

String formatGoogleSignInError(Object error) {
  if (error is PlatformException) {
  switch (error.code) {
    case GoogleSignIn.kSignInCanceledError:
      return 'Google sign-in was canceled. Please try again.';
    case GoogleSignIn.kSignInFailedError:
      return 'Google sign-in failed. Please make sure Google Play Services is up to date.';
    case GoogleSignIn.kNetworkError:
      return 'A network error occurred. Please check your connection.';
    default:
      return 'Google sign-in could not be completed. Please try again.';
  }
}

  if (error.toString().contains('reauth')) {
    return 'Google account re-authentication failed. Please sign out of the Google account on your device and try again.';
  }

  return error.toString();
}

class LoginScreen extends StatefulWidget {
  final bool autoLogout;
  const LoginScreen({super.key, this.autoLogout = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final VideoPlayerController _videoController;
  
  bool _isPasswordVisible = false;
  bool _keepActive = true; 
  bool _logoutMessageShown = false; // Add flag to track if message was shown

  final Color primaryRed = const Color(0xFF8B1515); 
  final Color darkText = const Color(0xFF1E232C);
  final Color grayText = const Color(0xFF8391A1);
  final Color borderColor = const Color(0xFFE8ECF4);
  final Color goldBorder = const Color(0xFFE5C07B); 

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/atlascutesys.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _videoController.setLooping(true);
          _videoController.play();
        });
      });
    _loadCredentials();
    // _initGoogleSignIn();
    
    if (widget.autoLogout && !_logoutMessageShown) {
      _logoutMessageShown = true; // Mark as shown
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'You have been logged out due to inactivity. Please login again to continue.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: primaryRed,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  // Future<void> _initGoogleSignIn() async {
  //   final GoogleSignIn googleSignIn = GoogleSignIn(
  //     serverClientId: '140618226788-r55pqlat0o2vvlsc1on3j22e668a1hpq.apps.googleusercontent.com',
  //     scopes: const <String>['email', 'profile'],
  //   );
  // }

  Future<void> _loadCredentials() async {
    final email = await _secureStorage.read(key: 'saved_email');
    final password = await _secureStorage.read(key: 'saved_password');
    if (email != null && password != null) {
      setState(() {
        _usernameController.text = email;
        _passwordController.text = password;
        _keepActive = true;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (_keepActive) {
      await _secureStorage.write(key: 'saved_email', value: _usernameController.text);
      await _secureStorage.write(key: 'saved_password', value: _passwordController.text);
    } else {
      await _secureStorage.delete(key: 'saved_email');
      await _secureStorage.delete(key: 'saved_password');
    }
  }

  Future<void> _handleGoogleSignIn() async {
  try {
      // 1. Create instance AND pass the Client ID
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '140618226788-lt31psljafm1en4n3aajo054thn5kfin.apps.googleusercontent.com',
        scopes: const <String>['email', 'profile'],
      );

      // 2. Clear any existing session
      await googleSignIn.signOut();

        // 3. Attempt silent login
        GoogleSignInAccount? account = await googleSignIn.signInSilently();
        
        if (account == null) {
          // 4. Trigger the interactive sign-in modal
          account = await googleSignIn.signIn();
        }
        
        // ... continue with your authentication logic ...

      if (!mounted) return;

      final GoogleSignInAuthentication auth = await account!.authentication;
      if (auth.idToken != null && auth.idToken!.isNotEmpty && mounted) {
        context.read<AuthBloc>().add(GoogleLoginRequested(idToken: auth.idToken!));
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in did not return an identity token. Please try again.')),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        await GoogleSignIn().signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatGoogleSignInError(error))),
        );
      }
    } catch (error) {
      if (mounted) {
        await GoogleSignIn().signOut();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatGoogleSignInError(error))),
        );
      }
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Locks the screen size so the keyboard overlays instead of squishing the UI
      resizeToAvoidBottomInset: false, 
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthSuccess) {
            _saveCredentials();
            Widget targetScreen = state.role == 'faculty'
                ? const FacultyDashboardScreen()
                : const StudentDashboardScreen();

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => targetScreen),
            );
          } else if (state is GoogleUserNotFound) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SignupScreen(
                  prefillEmail: state.email,
                  prefillName: state.name,
                ),
              ),
            );
          } else if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: Colors.red.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // 1. BACKGROUND LAYER: The Video Mascot
              // Anchored strictly to the bottom center of the screen
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 180, // Slightly taller so it sits beautifully behind the form
                  child: _videoController.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController.value.aspectRatio,
                          child: VideoPlayer(_videoController),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              
              // 2. FOREGROUND LAYER: The Logo and Form
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Pushes the logo down slightly from the very top notch
                      const SizedBox(height: 50),
                      
                      // BIGGER LOGO
                      Image.asset(
                        'assets/images/Frame 4.png',
                        height: 120, // Increased for a stronger presence
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Batangas State University — Lipa Campus',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: grayText,
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // --- START OF FORM ---
                      Text(
                        'SR-CODE / INSTITUTIONAL EMAIL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: grayText,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          hintText: '12-34567@g.batstate-u.edu.ph',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.email_outlined, color: grayText),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: borderColor, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: borderColor, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: primaryRed, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      Text(
                        'SECURE PASSWORD',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: grayText,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          hintText: '••••••••••••',
                          hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 2.0),
                          prefixIcon: Icon(Icons.lock_outline, color: grayText),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                              color: grayText,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: borderColor, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: borderColor, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            borderSide: BorderSide(color: primaryRed, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _keepActive,
                                  activeColor: primaryRed,
                                  side: BorderSide(color: borderColor, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4.0),
                                  ),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      _keepActive = value ?? false;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Keep active',
                                style: TextStyle(
                                  color: darkText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ForgotPasswordScreen(
                                    initialEmail: _usernameController.text.trim(),
                                  ),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: primaryRed,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      ElevatedButton(
                        onPressed: state is AuthLoading ? null : () {
                          context.read<AuthBloc>().add(LoginRequested(
                            email: _usernameController.text,
                            password: _passwordController.text,
                          ));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          side: BorderSide(color: goldBorder, width: 2.0),
                          elevation: 0,
                          disabledBackgroundColor: primaryRed.withValues(alpha: 0.5),
                        ),
                        child: state is AuthLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'LOGIN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),
                      
                      Row(
                        children: [
                          Expanded(child: Divider(color: borderColor)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR', style: TextStyle(color: grayText, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(child: Divider(color: borderColor)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      OutlinedButton(
                        onPressed: _handleGoogleSignIn,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: borderColor, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // TextButton(
                      //   onPressed: () {
                      //     Navigator.push(
                      //       context,
                      //       MaterialPageRoute(
                      //         builder: (context) => SignupScreen(
                      //           prefillEmail: _usernameController.text.trim(),
                      //           prefillName: '',
                      //         ),
                      //       ),
                      //     );
                      //   },
                      //   // child: Text(
                      //   //   "Don't have an account? Sign up",
                      //   //   style: TextStyle(
                      //   //     color: primaryRed,
                      //   //     fontWeight: FontWeight.w600,
                      //   //   ),
                        // ),
                      // ),
                      
                      // Bottom padding so the form doesn't hit the absolute edge of the screen
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
