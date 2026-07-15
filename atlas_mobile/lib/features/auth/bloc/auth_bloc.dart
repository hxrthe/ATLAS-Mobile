import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {

    // When the UI sends a LoginRequested event, execute this logic:
    on<LoginRequested>((event, emit) async {

      // 1. Immediately tell the UI to show a loading wheel
      emit(AuthLoading());

      try {
        // 2. Ask the repository to verify the credentials and return the data map
        final loginData = await authRepository.login(
          email: event.email,
          password: event.password,
        );

        // 3. Tell the UI it's a success and extract ONLY the role string from the map
        emit(AuthSuccess(role: loginData['role']!));

      } catch (e) {
        // 4. If the repository throws an error, send the error message to the UI
        emit(AuthFailure(error: e.toString()));
      }
    });
  }
}