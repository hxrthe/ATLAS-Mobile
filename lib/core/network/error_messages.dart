import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

const String _genericMessage = 'Something went wrong. Please try again.';
const String _noInternetMessage =
    'No internet connection. Please check your connection and try again.';
const String _timeoutMessage =
    'The server is taking too long to respond. Please check your connection and try again.';
const String _serverMessage =
    'Something went wrong on our end. Please try again in a few moments.';
const String _serverWakingMessage =
    'The server is temporarily unavailable or starting up. Please try again in a minute.';
const String _unexpectedDataMessage =
    'We received unexpected data from the server. Please try again.';

final RegExp _technicalPattern = RegExp(
  r"\b\w+(Exception|Error)\b|Instance of '|Null check|is not a subtype|"
  r'Traceback|<!DOCTYPE|<html|status code of|RequestOptions|StackTrace',
  caseSensitive: false,
);

/// Converts any thrown error into a short, plain-language message that a
/// non-technical user can understand. Pass [fallback] to describe what failed
/// (e.g. "Could not load your courses.") when no better message is available.
String friendlyError(Object? error, {String? fallback}) {
  final defaultMessage = fallback ?? _genericMessage;

  if (error == null) return defaultMessage;
  if (error is DioException) return _fromDio(error, defaultMessage);
  if (error is SocketException) return _noInternetMessage;
  if (error is TimeoutException) return _timeoutMessage;
  if (error is HttpException) return _noInternetMessage;
  if (error is FormatException || error is TypeError) {
    return _unexpectedDataMessage;
  }

  final message = error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|Error):\s*'), '')
      .trim();
  return _isReadable(message) ? message : defaultMessage;
}

String _fromDio(DioException e, String defaultMessage) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return _timeoutMessage;
    case DioExceptionType.connectionError:
      return _noInternetMessage;
    case DioExceptionType.badCertificate:
      return 'A secure connection to the server could not be made. Please try again later.';
    case DioExceptionType.cancel:
      return 'The request was cancelled. Please try again.';
    case DioExceptionType.badResponse:
      return _fromStatus(e.response?.statusCode, e.response?.data, defaultMessage);
    case DioExceptionType.unknown:
      if (e.error is SocketException || e.error is HttpException) {
        return _noInternetMessage;
      }
      if (e.error is TimeoutException) return _timeoutMessage;
      return defaultMessage;
  }
}

String _fromStatus(int? status, dynamic data, String defaultMessage) {
  final serverMessage = _serverDetail(data);

  if (status == null) return defaultMessage;
  if (status == 502 || status == 503 || status == 504) {
    return _serverWakingMessage;
  }
  if (status >= 500) return _serverMessage;

  switch (status) {
    case 400:
    case 422:
      return serverMessage ??
          'Some of the information provided is invalid. Please review it and try again.';
    case 401:
      return serverMessage ?? 'Your session has expired. Please sign in again.';
    case 403:
      return serverMessage ?? "You don't have permission to do this.";
    case 404:
      return "We couldn't find what you were looking for. It may have been moved or deleted.";
    case 408:
      return _timeoutMessage;
    case 409:
      return serverMessage ??
          'This conflicts with existing data. Please refresh and try again.';
    case 413:
      return 'The file is too large to upload. Please try a smaller one.';
    case 429:
      return 'Too many requests. Please wait a moment and try again.';
  }
  return serverMessage ?? defaultMessage;
}

/// Extracts a readable message from a backend error body such as
/// `{"detail": "..."}` or `{"field": ["..."]}`.
String? _serverDetail(dynamic data) {
  if (data is String) return _isReadable(data) ? data.trim() : null;
  if (data is! Map) return null;

  for (final key in ['detail', 'message', 'error']) {
    final value = data[key];
    if (value is String && _isReadable(value)) return value.trim();
  }
  for (final entry in data.entries) {
    if (entry.key == 'status_code' || entry.key == 'success') continue;
    final value = entry.value;
    final text = value is List && value.isNotEmpty
        ? value.first.toString()
        : value is String
            ? value
            : null;
    if (text != null && _isReadable(text)) return text.trim();
  }
  return null;
}

bool _isReadable(String message) {
  final text = message.trim();
  return text.isNotEmpty &&
      text.length <= 300 &&
      !_technicalPattern.hasMatch(text);
}
