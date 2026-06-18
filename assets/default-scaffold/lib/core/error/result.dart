import 'package:__PKG__/core/error/failures.dart';

/// A lightweight `Result` type so the domain/data layers can report success or
/// a domain [AppFailure] without leaking infrastructure exceptions to the UI.
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
