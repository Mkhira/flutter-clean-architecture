import 'package:json_annotation/json_annotation.dart';
import 'package:__PKG__/features/products/data/models/product_category_model.dart';
import 'package:__PKG__/features/products/domain/entities/product.dart';
import 'package:__PKG__/features/products/domain/entities/product_category.dart';

part 'product_model.g.dart';

@JsonSerializable()
class ProductModel {
  const ProductModel({
    required this.id,
    this.name,
    this.price,
    this.category,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) =>
      _$ProductModelFromJson(json);

  final int id;
  final String? name;
  final double? price;
  final ProductCategoryModel? category;

  Map<String, dynamic> toJson() => _$ProductModelToJson(this);

  Product toEntity() => Product(
    id: id,
    name: name ?? '',
    price: price ?? 0,
    category: category?.toEntity() ?? const ProductCategory(id: 0, name: ''),
  );
}
