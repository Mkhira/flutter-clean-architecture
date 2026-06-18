import 'package:equatable/equatable.dart';
import 'package:__PKG__/features/products/domain/entities/product_category.dart';

final class Product extends Equatable {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
  });

  final int id;
  final String name;
  final double price;
  final ProductCategory category;

  @override
  List<Object?> get props => [id, name, price, category];
}
