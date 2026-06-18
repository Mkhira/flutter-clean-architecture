import 'package:dio/dio.dart';
import 'package:__PKG__/core/error/error_mapper.dart';
import 'package:__PKG__/core/error/failures.dart';
import 'package:__PKG__/core/error/result.dart';
import 'package:__PKG__/features/products/data/datasources/products_remote_data_source.dart';
import 'package:__PKG__/features/products/domain/entities/paginated_products.dart';
import 'package:__PKG__/features/products/domain/repositories/products_repository.dart';

final class ProductsRepositoryImpl implements ProductsRepository {
  const ProductsRepositoryImpl(this._remoteDataSource);

  final ProductsRemoteDataSource _remoteDataSource;

  @override
  Future<Result<PaginatedProducts>> getProducts({int page = 1}) async {
    try {
      final pageModel = await _remoteDataSource.getProducts(page: page);
      return Success(pageModel.toEntity());
    } on DioException catch (error) {
      return FailureResult(mapDioException(error));
    } on Exception {
      return const FailureResult(
        UnknownFailure(message: 'common.unknown_error'),
      );
    }
  }
}
