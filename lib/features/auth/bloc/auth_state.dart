import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthSuccess extends AuthState {
  final String role;

  const AuthSuccess({required this.role});

  @override
  List<Object> get props => [role];
}

class AuthFailure extends AuthState {
  final String error;

  const AuthFailure({required this.error});

  @override
  List<Object> get props => [error];
}

class ForgotPasswordEmailSent extends AuthState {
  final String email;
  const ForgotPasswordEmailSent({required this.email});

  @override
  List<Object> get props => [email];
}

class OtpVerified extends AuthState {
  final String resetToken;
  const OtpVerified({required this.resetToken});

  @override
  List<Object> get props => [resetToken];
}

class PasswordResetSuccess extends AuthState {}

class GoogleUserNotFound extends AuthState {
  final String email;
  final String name;

  const GoogleUserNotFound({required this.email, required this.name});

  @override
  List<Object> get props => [email, name];
}
