import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:__PKG__/core/error/result.dart';
import 'package:__PKG__/features/products/domain/entities/paginated_products.dart';
import 'package:__PKG__/features/products/domain/entities/product.dart';
import 'package:__PKG__/features/products/domain/entities/product_category.dart';
import 'package:__PKG__/features/products/domain/usecases/get_products_use_case.dart';
import 'package:__PKG__/features/products/presentation/bloc/products_bloc.dart';

class _MockGetProductsUseCase extends Mock implements GetProductsUseCase {}

Product _product(int id) => Product(
  id: id,
  name: 'Product #$id',
  price: id.toDouble(),
  category: const ProductCategory(id: 0, name: 'Audio'),
);

void main() {
  late GetProductsUseCase useCase;

  final page1 = PaginatedProducts(
    products: [_product(1), _product(2)],
    page: 1,
    totalPages: 2,
  );
  final page2 = PaginatedProducts(
    products: [_product(3), _product(4)],
    page: 2,
    totalPages: 2,
  );

  setUp(() => useCase = _MockGetProductsUseCase());

  blocTest<ProductsBloc, ProductsState>(
    'appends the next page and sets hasReachedMax at the end',
    build: () {
      when(() => useCase()).thenAnswer((_) async => Success(page1));
      when(() => useCase(page: 2)).thenAnswer((_) async => Success(page2));
      return ProductsBloc(useCase);
    },
    act: (bloc) async {
      bloc.add(const ProductsFetched());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bloc.add(const ProductsFetched());
    },
    expect: () => [
      ProductsState(
        status: ProductsStatus.success,
        products: page1.products,
        page: 1,
      ),
      ProductsState(
        status: ProductsStatus.success,
        products: [...page1.products, ...page2.products],
        page: 2,
        hasReachedMax: true,
      ),
    ],
  );

  blocTest<ProductsBloc, ProductsState>(
    'ProductsRefreshed reloads from page 1 and replaces the list',
    build: () {
      when(() => useCase()).thenAnswer((_) async => Success(page1));
      return ProductsBloc(useCase);
    },
    seed: () => ProductsState(
      status: ProductsStatus.success,
      products: [...page1.products, ...page2.products],
      page: 2,
      hasReachedMax: true,
    ),
    act: (bloc) => bloc.add(const ProductsRefreshed()),
    expect: () => [
      ProductsState(
        status: ProductsStatus.success,
        products: page1.products,
        page: 1,
      ),
    ],
  );
}
