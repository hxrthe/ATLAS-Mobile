import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

enum AuthLoadingSource { email, google, other }

class AuthLoading extends AuthState {
  final AuthLoadingSource source;

  const AuthLoading({this.source = AuthLoadingSource.other});

  @override
  List<Object?> get props => [source];
}

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
