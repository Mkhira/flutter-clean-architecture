# Networking (Dio + Retrofit)

## Rules

- Use one configured Dio singleton through DI.
- Configure `BaseOptions` with baseUrl, timeouts, headers.
- Add interceptors carefully.
- Add logging only in debug/dev and never log secrets/tokens.
- Retrofit API clients live in the data layer.
- Datasources call Retrofit clients.
- Repositories map data models to domain entities.
- Repositories map Dio/API errors into domain failures/results.
- UI must never catch or display raw `DioException`.

## Example folder

```text
core/network/dio_client.dart
core/network/interceptors/auth_interceptor.dart
features/auth/data/datasources/auth_remote_data_source.dart
features/auth/data/models/login_request_model.dart
features/auth/data/models/login_response_model.dart
features/auth/data/api/auth_api_client.dart
```

## Retrofit pattern

```dart
@RestApi()
abstract class AuthApiClient {
  factory AuthApiClient(Dio dio, {String? baseUrl}) = _AuthApiClient;

  @POST('/auth/login')
  Future<LoginResponseModel> login(@Body() LoginRequestModel body);
}
```

Generated file part directive:

```dart
part 'auth_api_client.g.dart';
```

After editing Retrofit interfaces or models, run build_runner.

## Dio configuration

```dart
Dio createDio({
  required String baseUrl,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  return dio;
}
```

## Errors

- Catch `DioException` in the repository or an error mapper.
- Convert it to `AppFailure` (see `errors-and-results.md`).
- Never expose `DioException` to Cubit/UI directly unless the project explicitly
  does so.
