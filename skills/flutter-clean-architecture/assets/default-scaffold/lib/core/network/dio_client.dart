import 'package:dio/dio.dart';

/// Builds the single configured [Dio] instance shared through DI.
/// Add interceptors here (auth, logging) — never log secrets/tokens.
Dio createDio({required String baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
}
