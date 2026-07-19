import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// STRICT RELATIVE IMPORTS
import 'core/network/api_client.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://dnkpupegpijryhaffgbc.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRua3B1cGVncGlqcnloYWZmZ2JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQzNzgwMjIsImV4cCI6MjA5OTk1NDAyMn0.cmkMyRLeWr6boIci9ztpN5AKuYhgXXnivYn5f2hkndw',
  );

  runApp(const AtlasMobileApp());
}

class AtlasMobileApp extends StatelessWidget {
  const AtlasMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    // We keep the Repository global so the whole app can access the database connection
    return RepositoryProvider(
      create: (context) => AuthRepository(),
      child: BlocProvider(
        create: (context) => AuthBloc(
          authRepository: context.read<AuthRepository>(),
        ),
        child: MaterialApp(
          title: 'ATLAS Mobile',
          debugShowCheckedModeBanner: false,
          navigatorKey: ApiClient.navigatorKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B1515)),
            useMaterial3: true,
          ),
          home: const LoginScreen(),
        ),
      ),
    );
  }
}