import 'package:__PKG__/core/error/result.dart';
import 'package:__PKG__/features/products/domain/entities/paginated_products.dart';

abstract interface class ProductsRepository {
  Future<Result<PaginatedProducts>> getProducts({int page});
}
