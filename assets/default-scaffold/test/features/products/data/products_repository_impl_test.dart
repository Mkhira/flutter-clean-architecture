import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:__PKG__/core/error/failures.dart';
import 'package:__PKG__/core/error/result.dart';
import 'package:__PKG__/features/products/data/datasources/products_remote_data_source.dart';
import 'package:__PKG__/features/products/data/models/product_category_model.dart';
import 'package:__PKG__/features/products/data/models/product_model.dart';
import 'package:__PKG__/features/products/data/models/products_page_model.dart';
import 'package:__PKG__/features/products/data/repositories/products_repository_impl.dart';
import 'package:__PKG__/features/products/domain/entities/paginated_products.dart';

class _MockRemoteDataSource extends Mock implements ProductsRemoteDataSource {}

void main() {
  late ProductsRemoteDataSource dataSource;
  late ProductsRepositoryImpl repository;

  setUp(() {
    dataSource = _MockRemoteDataSource();
    repository = ProductsRepositoryImpl(dataSource);
  });

  const pageModel = ProductsPageModel(
    items: [
      ProductModel(
        id: 1,
        name: 'Product #1',
        price: 9.99,
        category: ProductCategoryModel(id: 0, name: 'Audio'),
      ),
    ],
    pageSize: 10,
    total: 1,
  );

  test('maps a page model to a Success<PaginatedProducts>', () async {
    when(
      () => dataSource.getProducts(page: 1),
    ).thenAnswer((_) async => pageModel);

    final result = await repository.getProducts();

    expect(result, isA<Success<PaginatedProducts>>());
    final data = (result as Success<PaginatedProducts>).data;
    expect(data.products.single.name, 'Product #1');
    expect(data.hasReachedMax, isTrue);
  });

  test('maps a DioException to a NetworkFailure', () async {
    when(() => dataSource.getProducts(page: 1)).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/products'),
        type: DioExceptionType.connectionError,
      ),
    );

    final result = await repository.getProducts();

    expect(result, isA<FailureResult<dynamic>>());
    expect((result as FailureResult).failure, isA<NetworkFailure>());
  });
}
