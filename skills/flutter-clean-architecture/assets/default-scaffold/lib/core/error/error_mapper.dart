import 'package:dio/dio.dart';
import 'package:__PKG__/core/error/failures.dart';

/// Maps an infrastructure [DioException] into a domain [AppFailure].
/// All branches carry a localization key, not a user-visible string.
AppFailure mapDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return const NetworkFailure(message: 'common.network_error');
    case DioExceptionType.badResponse:
      return const ServerFailure(message: 'common.server_error');
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return const UnknownFailure(message: 'common.unknown_error');
  }
}
