import 'package:json_annotation/json_annotation.dart';
import 'package:__PKG__/features/products/domain/entities/product_category.dart';

part 'product_category_model.g.dart';

@JsonSerializable()
class ProductCategoryModel {
  const ProductCategoryModel({this.id, this.name});

  factory ProductCategoryModel.fromJson(Map<String, dynamic> json) =>
      _$ProductCategoryModelFromJson(json);

  final int? id;
  final String? name;

  Map<String, dynamic> toJson() => _$ProductCategoryModelToJson(this);

  ProductCategory toEntity() => ProductCategory(id: id ?? 0, name: name ?? '');
}
