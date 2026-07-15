import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

// UPDATED: Now requires a role string
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