import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// App-level exceptions — prefixed with "App" to avoid clashing with
// Supabase's own AuthException, FunctionException, StorageException
// ─────────────────────────────────────────────────────────────────────────────

sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AppAuthException extends AppException {
  const AppAuthException(super.message);
}

class DatabaseException extends AppException {
  const DatabaseException(super.message);
}

class AppStorageException extends AppException {
  const AppStorageException(super.message);
}

class AppFunctionException extends AppException {
  const AppFunctionException(super.message);
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'Check your internet connection']);
}

class PermissionException extends AppException {
  const PermissionException([
    super.message = 'You do not have permission to perform this action',
  ]);
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

// Maps Supabase AuthException to our AppAuthException
AppAuthException mapSupabaseAuthError(AuthException e) {
  final msg = e.message.toLowerCase();
  if (msg.contains('invalid login credentials') ||
      msg.contains('invalid email or password')) {
    return const AppAuthException('Incorrect phone number or password');
  }
  if (msg.contains('user already registered') ||
      msg.contains('already been registered')) {
    return const AppAuthException(
      'An account with this phone number already exists',
    );
  }
  if (msg.contains('email not confirmed')) {
    return const AppAuthException('Please verify your account first');
  }
  if (msg.contains('too many requests')) {
    return const AppAuthException('Too many attempts, please try again later');
  }
  if (msg.contains('network') || msg.contains('connection')) {
    return const AppAuthException('Check your internet connection');
  }
  if (msg.contains('email address') && msg.contains('invalid')) {
    return const AppAuthException(
      'Registration failed due to a server configuration issue. Please contact support.',
    );
  }
  return AppAuthException(e.message);
}

// Maps Supabase PostgrestException to DatabaseException
DatabaseException mapPostgrestError(PostgrestException e) {
  return switch (e.code) {
    '23505' => const DatabaseException(
      'A record with this value already exists',
    ),
    '23503' => const DatabaseException('Related record not found'),
    '42501' => const DatabaseException(
      'You do not have permission to perform this action',
    ),
    _ => DatabaseException('Database error: ${e.message}'),
  };
}
