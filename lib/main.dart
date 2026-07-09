import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// STRICT RELATIVE IMPORTS
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/login_screen.dart';

void main() {
  runApp(const AtlasMobileApp());
}

class AtlasMobileApp extends StatelessWidget {
  const AtlasMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    // We keep the Repository global so the whole app can access the database connection
    return RepositoryProvider(
      create: (context) => AuthRepository(),
      child: MaterialApp(
        title: 'ATLAS Mobile',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B1515)),
          useMaterial3: true,
        ),
        // INJECT THE BLOC DIRECTLY INTO THE ROUTE
        home: BlocProvider(
          create: (context) => AuthBloc(
            authRepository: context.read<AuthRepository>(),
          ),
          child: const LoginScreen(),
        ),
      ),
    );
  }
}