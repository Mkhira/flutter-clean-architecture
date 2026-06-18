# Dependency Injection (GetIt)

## Rules

- Put the service locator in `core/di/`.
- Use `GetIt.instance`.
- Register infrastructure first, then clients, datasources, repositories,
  usecases, cubits/blocs.
- Use `registerLazySingleton` for Dio, API clients, repositories, datasources.
- Use `registerFactory` for Cubits/Blocs.
- Use `registerSingleton` only for long-lived stateful services.
- Use async registration only when initialization requires `await`.
- In tests, reset GetIt between tests.

## Example

```dart
// Annotate the type explicitly — under `very_good_analysis` a bare
// `final getIt = GetIt.instance;` trips `specify_nonobvious_property_types`.
final GetIt getIt = GetIt.instance;

Future<void> configureDependencies() async {
  getIt
    ..registerLazySingleton<Dio>(() => createDio(baseUrl: Env.baseUrl))
    ..registerLazySingleton<AuthApiClient>(() => AuthApiClient(getIt<Dio>()))
    ..registerLazySingleton<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(getIt<AuthApiClient>()),
    )
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(getIt<AuthRemoteDataSource>()),
    )
    ..registerLazySingleton(() => LoginUseCase(getIt<AuthRepository>()))
    ..registerFactory(() => LoginCubit(getIt<LoginUseCase>()));
}
```

## More rules

- Do not call `GetIt.instance` everywhere in domain code.
- Prefer constructor injection.
- UI may use DI to create a Cubit/Bloc at composition boundaries (e.g. inside a
  `BlocProvider` at the page entry).
- Tests should inject mocks through constructors where possible.
