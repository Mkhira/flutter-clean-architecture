# Errors and Results

The skill must not leak infrastructure exceptions into UI.

## Recommended simple custom pattern

```dart
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.data);
  final T data;
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);
  final AppFailure failure;
}
```

## Failures

```dart
// `implements Exception` lets stacks that surface failures by throwing
// (e.g. a Riverpod AsyncNotifier) do so without tripping `only_throw_errors`.
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
```

**Alternative:** use `fpdart` `Either<AppFailure, T>` if the project already uses
it or the user wants a functional style.

## Rules

- Datasource may throw/receive `DioException`.
- Repository catches infrastructure errors and returns a domain failure/result.
- Cubit/Bloc receives a domain result.
- UI displays a localized, user-safe message.
- Log technical details only in debug/dev, never to the user.

## Example mapper

All branches return `const` constructors.

```dart
AppFailure mapDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return const NetworkFailure(message: 'common.network_error');
    case DioExceptionType.badResponse:
      return const ServerFailure(message: 'common.server_error');
    default:
      return const UnknownFailure(message: 'common.unknown_error');
  }
}
```

> `message` here carries a **localization key**, not a user-visible string. The
> key is resolved with `.tr()` at the UI boundary so failures stay
> infrastructure-agnostic and translatable.
