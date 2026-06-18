import 'package:__PKG__/features/products/data/api/products_api_client.dart';
import 'package:__PKG__/features/products/data/models/products_page_model.dart';

/// Datasource contract. `abstract interface class` so it stays mockable and
/// the fake / Retrofit impls are interchangeable in DI.
abstract interface class ProductsRemoteDataSource {
  Future<ProductsPageModel> getProducts({int page});
}

/// Retrofit-backed implementation. Wire this into DI (in place of the fake)
/// once a real backend exists.
final class ProductsRemoteDataSourceImpl implements ProductsRemoteDataSource {
  const ProductsRemoteDataSourceImpl(this._client);

  final ProductsApiClient _client;

  @override
  Future<ProductsPageModel> getProducts({int page = 1}) =>
      _client.getProducts(page);
}
