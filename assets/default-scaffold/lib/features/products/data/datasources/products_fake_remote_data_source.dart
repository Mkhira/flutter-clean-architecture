import 'package:__PKG__/features/products/data/datasources/products_remote_data_source.dart';
import 'package:__PKG__/features/products/data/models/product_category_model.dart';
import 'package:__PKG__/features/products/data/models/product_model.dart';
import 'package:__PKG__/features/products/data/models/products_page_model.dart';

/// Seeded, paginated sample data so the app displays real-looking products
/// with no backend. Returns the same [ProductsPageModel] the Retrofit-backed
/// datasource returns — swap it in DI for the real impl when the API exists.
final class ProductsFakeRemoteDataSource implements ProductsRemoteDataSource {
  const ProductsFakeRemoteDataSource();

  static const int _total = 25;
  static const int _pageSize = 10;

  @override
  Future<ProductsPageModel> getProducts({int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize) > _total ? _total : start + _pageSize;
    final items = <ProductModel>[
      for (var id = start + 1; id <= end; id++) _buildProduct(id),
    ];
    return ProductsPageModel(
      items: items,
      page: page,
      pageSize: _pageSize,
      total: _total,
      totalPages: (_total / _pageSize).ceil(),
    );
  }

  ProductModel _buildProduct(int id) {
    const categories = ['Audio', 'Wearables', 'Computers', 'Accessories'];
    final categoryIndex = id % categories.length;
    return ProductModel(
      id: id,
      name: 'Product #$id',
      price: 9.99 + id,
      category: ProductCategoryModel(
        id: categoryIndex,
        name: categories[categoryIndex],
      ),
    );
  }
}
