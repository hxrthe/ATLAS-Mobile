import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;

  const LoginRequested({required this.email, required this.password});

  @override
  List<Object> get props => [email, password];
}

class GoogleLoginRequested extends AuthEvent {
  const GoogleLoginRequested();
}

class ForgotPasswordRequested extends AuthEvent {
  final String email;

  const ForgotPasswordRequested({required this.email});

  @override
  List<Object> get props => [email];
}

class VerifyOtpRequested extends AuthEvent {
  final String email;
  final String otp;

  const VerifyOtpRequested({required this.email, required this.otp});

  @override
  List<Object> get props => [email, otp];
}

class ResetPasswordRequested extends AuthEvent {
  final String resetToken;
  final String newPassword;

  const ResetPasswordRequested({required this.resetToken, required this.newPassword});

  @override
  List<Object> get props => [resetToken, newPassword];
}

class SignupRequested extends AuthEvent {
  final String email;
  final String password;
  final String name;
  final String studentId;
  final String course;
  final String section;
  final String yearLevel;

  const SignupRequested({
    required this.email,
    required this.password,
    required this.name,
    required this.studentId,
    required this.course,
    required this.section,
    required this.yearLevel,
  });

  @override
  List<Object> get props => [email, password, name, studentId, course, section, yearLevel];
}
