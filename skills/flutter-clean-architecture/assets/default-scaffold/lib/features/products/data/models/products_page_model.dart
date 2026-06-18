import 'package:json_annotation/json_annotation.dart';
import 'package:__PKG__/features/products/data/models/product_model.dart';
import 'package:__PKG__/features/products/domain/entities/paginated_products.dart';

part 'products_page_model.g.dart';

/// Response envelope for a page of products. Both the Retrofit-backed and the
/// fake datasource return this exact type, so everything above the datasource
/// is identical for either.
@JsonSerializable()
class ProductsPageModel {
  const ProductsPageModel({
    this.items = const [],
    this.page = 1,
    this.pageSize = 0,
    this.total = 0,
    this.totalPages = 1,
  });

  factory ProductsPageModel.fromJson(Map<String, dynamic> json) =>
      _$ProductsPageModelFromJson(json);

  final List<ProductModel> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  Map<String, dynamic> toJson() => _$ProductsPageModelToJson(this);

  PaginatedProducts toEntity() => PaginatedProducts(
    products: items.map((m) => m.toEntity()).toList(),
    page: page,
    totalPages: totalPages,
  );
}
