sealed class Failure {
  const Failure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

class FunctionFailure extends Failure {
  const FunctionFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Check your internet connection']);
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'You do not have permission']);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unexpected error occurred']);
}
