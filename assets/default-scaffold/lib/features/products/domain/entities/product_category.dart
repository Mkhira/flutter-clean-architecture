import 'package:equatable/equatable.dart';

final class ProductCategory extends Equatable {
  const ProductCategory({required this.id, required this.name});

  final int id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}
