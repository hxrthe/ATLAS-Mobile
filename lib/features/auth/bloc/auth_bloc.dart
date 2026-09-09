import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<LoginRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        final role = await authRepository.login(
          email: event.email,
          password: event.password,
        );
        emit(AuthSuccess(role: role));
      } catch (e) {
        emit(AuthFailure(error: e.toString().replaceAll('Exception: ', '')));
      }
    });

    on<GoogleLoginRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        final result = await authRepository.loginWithGoogle();
        emit(AuthSuccess(role: result['role'] as String));
      } catch (e) {
        emit(AuthFailure(error: e.toString().replaceAll('Exception: ', '')));
      }
    });

    on<ForgotPasswordRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        await authRepository.requestPasswordReset(event.email);
        emit(ForgotPasswordEmailSent(email: event.email));
      } catch (e) {
        emit(AuthFailure(error: e.toString()));
      }
    });

    on<VerifyOtpRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        final resetToken = await authRepository.verifyPasswordResetOtp(
          event.email,
          event.otp,
        );
        emit(OtpVerified(resetToken: resetToken));
      } catch (e) {
        emit(AuthFailure(error: e.toString()));
      }
    });

    on<ResetPasswordRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        await authRepository.confirmPasswordReset(
          event.resetToken,
          event.newPassword,
        );
        emit(PasswordResetSuccess());
      } catch (e) {
        emit(AuthFailure(error: e.toString()));
      }
    });
  }
}
