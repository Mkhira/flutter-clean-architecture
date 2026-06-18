import 'package:dio/dio.dart';
import 'package:__PKG__/features/products/data/models/products_page_model.dart';
import 'package:retrofit/retrofit.dart';

part 'products_api_client.g.dart';

@RestApi()
abstract class ProductsApiClient {
  factory ProductsApiClient(Dio dio, {String? baseUrl}) = _ProductsApiClient;

  @GET('/products')
  Future<ProductsPageModel> getProducts(@Query('page') int page);
}
