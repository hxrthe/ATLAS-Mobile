import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/error_messages.dart';
import '../auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<LoginRequested>((event, emit) async {
      emit(const AuthLoading(source: AuthLoadingSource.email));
      try {
        final role = await authRepository.login(
          email: event.email,
          password: event.password,
        );
        emit(AuthSuccess(role: role));
      } catch (e) {
        emit(AuthFailure(
          error: friendlyError(e, fallback: 'Could not sign you in. Please try again.'),
        ));
      }
    });

    on<GoogleLoginRequested>((event, emit) async {
      emit(const AuthLoading(source: AuthLoadingSource.google));
      try {
        final result = await authRepository.loginWithGoogle();
        emit(AuthSuccess(role: result['role'] as String));
      } catch (e) {
        emit(AuthFailure(
          error: friendlyError(e, fallback: 'Google sign-in failed. Please try again.'),
        ));
      }
    });

    on<ForgotPasswordRequested>((event, emit) async {
      emit(const AuthLoading());
      try {
        await authRepository.requestPasswordReset(event.email);
        emit(ForgotPasswordEmailSent(email: event.email));
      } catch (e) {
        emit(AuthFailure(
          error: friendlyError(e, fallback: 'Could not send the reset code. Please try again.'),
        ));
      }
    });

    on<VerifyOtpRequested>((event, emit) async {
      emit(const AuthLoading());
      try {
        final resetToken = await authRepository.verifyPasswordResetOtp(
          event.email,
          event.otp,
        );
        emit(OtpVerified(resetToken: resetToken));
      } catch (e) {
        emit(AuthFailure(
          error: friendlyError(e, fallback: 'The code is invalid or has expired.'),
        ));
      }
    });

    on<ResetPasswordRequested>((event, emit) async {
      emit(const AuthLoading());
      try {
        await authRepository.confirmPasswordReset(
          event.resetToken,
          event.newPassword,
        );
        emit(PasswordResetSuccess());
      } catch (e) {
        emit(AuthFailure(
          error: friendlyError(e, fallback: 'Could not reset your password. Please try again.'),
        ));
      }
    });
  }
}
