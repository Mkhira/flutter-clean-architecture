import 'package:equatable/equatable.dart';
import 'package:__PKG__/features/products/domain/entities/product.dart';

/// Pagination metadata is a domain entity so the Bloc can decide
/// `hasReachedMax` without knowing anything about the transport layer.
final class PaginatedProducts extends Equatable {
  const PaginatedProducts({
    required this.products,
    required this.page,
    required this.totalPages,
  });

  final List<Product> products;
  final int page;
  final int totalPages;

  bool get hasReachedMax => page >= totalPages;

  @override
  List<Object?> get props => [products, page, totalPages];
}
