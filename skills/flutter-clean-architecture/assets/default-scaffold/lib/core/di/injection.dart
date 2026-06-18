import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:__PKG__/core/env/env.dart';
import 'package:__PKG__/core/network/dio_client.dart';
import 'package:__PKG__/features/products/data/datasources/products_fake_remote_data_source.dart';
import 'package:__PKG__/features/products/data/datasources/products_remote_data_source.dart';
import 'package:__PKG__/features/products/data/repositories/products_repository_impl.dart';
import 'package:__PKG__/features/products/domain/repositories/products_repository.dart';
import 'package:__PKG__/features/products/domain/usecases/get_products_use_case.dart';
import 'package:__PKG__/features/products/presentation/bloc/products_bloc.dart';
import 'package:__PKG__/features/settings/presentation/bloc/settings_bloc.dart';

final GetIt getIt = GetIt.instance;

Future<void> configureDependencies() async {
  getIt
    // Infrastructure
    ..registerLazySingleton<Dio>(() => createDio(baseUrl: Env.baseUrl))
    // Products: fake datasource by default (seeded, paginated, no backend).
    // Swap for ProductsRemoteDataSourceImpl(ProductsApiClient(getIt<Dio>()))
    // once the API exists — nothing upstream changes.
    ..registerLazySingleton<ProductsRemoteDataSource>(
      () => const ProductsFakeRemoteDataSource(),
    )
    ..registerLazySingleton<ProductsRepository>(
      () => ProductsRepositoryImpl(getIt<ProductsRemoteDataSource>()),
    )
    ..registerLazySingleton(
      () => GetProductsUseCase(getIt<ProductsRepository>()),
    )
    ..registerFactory(() => ProductsBloc(getIt<GetProductsUseCase>()))
    // Settings: long-lived app state -> lazy singleton.
    ..registerLazySingleton<SettingsBloc>(SettingsBloc.new);
}
