import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../student_dashboard/student_dashboard_screen.dart';

// STRICT RELATIVE IMPORTS
import '../faculty_dashboard/faculty_dashboard_screen.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _keepActive = true; 

  final Color primaryRed = const Color(0xFF8B1515); 
  final Color darkText = const Color(0xFF1E232C);
  final Color grayText = const Color(0xFF8391A1);
  final Color borderColor = const Color(0xFFE8ECF4);
  final Color goldBorder = const Color(0xFFE5C07B); 

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 1. Wrap the body in a BlocConsumer to listen to the AuthBloc
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          // 2. Listen for Success and route to the Dashboard
          if (state is AuthSuccess) {
            Widget targetScreen = state.role == 'faculty'
                ? FacultyDashboardScreen()
                : const StudentDashboardScreen();

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => targetScreen),
            );
          }
          // 3. Listen for Failure and show an error popup
          else if (state is AuthFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: Theme.of(context).colorScheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/Frame 4.png',
                    height: 120, 
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),

                  // For the Subtitle:
                  Text(
                    'Batangas State University — Lipa Campus',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant, // Readable gray in both modes
                      fontSize: 14,
                    ),
                  ),

// For the Input Labels:
                  Text(
                    'SR-CODE / USERNAME',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface, // Crisp and high contrast
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: '24-00214',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6)),
                      prefixIcon: Icon(Icons.email_outlined, color: grayText), // Make sure grayText is defined!
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainer,
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
                  const SizedBox(height: 24),

                  Text(
                    'SECURE PASSWORD',
                    style: TextStyle(
                      fontSize: 12,
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
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 2.0),
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
                      fillColor: Theme.of(context).colorScheme.surfaceContainer,
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
                  
                  // --- NEW PADDED ROW START ---
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: _keepActive, // Uses your specific state variable
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
                          onPressed: () {},
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
                  ),
                  const SizedBox(height: 24), // Gives the login button breathing room
                  // --- NEW PADDED ROW END ---

                  // 4. Update Button to handle Loading State
                  ElevatedButton(
                    // Disable button if already loading
                    onPressed: state is AuthLoading ? null : () {
                      // Dispatch the LoginRequested event to the BLoC
                      context.read<AuthBloc>().add(LoginRequested(
                        email: _usernameController.text,
                        password: _passwordController.text,
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary, // ATLAS Red
                      foregroundColor: Colors.white, // Forces the word "LOGIN" to stay pure white
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: goldBorder, width: 2.0),
                      elevation: 0, 
                      // Prevent grey background when disabled
                      disabledBackgroundColor: primaryRed.withOpacity(0.7),
                    ),
                    // Swap text for a loading spinner based on state
                    child: state is AuthLoading 
                        ? SizedBox(
                            height: 20, 
                            width: 20, 
                            child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'LOGIN',
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold, 
                              letterSpacing: 1.0
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}