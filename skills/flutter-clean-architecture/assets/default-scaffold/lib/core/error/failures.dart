/// Domain failures. `message` carries a **localization key** (resolved with
/// `.tr()` at the UI boundary), never a user-visible string.
///
/// `implements Exception` lets stacks that surface failures by throwing do so
/// without tripping `only_throw_errors`.
sealed class AppFailure implements Exception {
  const AppFailure({required this.message});
  final String message;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure({required super.message});
}

final class ServerFailure extends AppFailure {
  const ServerFailure({required super.message});
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({required super.message});
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure({required super.message});
}
