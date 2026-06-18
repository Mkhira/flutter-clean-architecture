import 'package:__PKG__/core/error/result.dart';
import 'package:__PKG__/features/products/domain/entities/paginated_products.dart';
import 'package:__PKG__/features/products/domain/repositories/products_repository.dart';

/// Plain `class` (not `final`) so cubit/bloc tests can mock it.
class GetProductsUseCase {
  const GetProductsUseCase(this._repository);

  final ProductsRepository _repository;

  Future<Result<PaginatedProducts>> call({int page = 1}) =>
      _repository.getProducts(page: page);
}
