part of 'products_bloc.dart';

enum ProductsStatus { initial, success, failure }

final class ProductsState extends Equatable {
  const ProductsState({
    this.status = ProductsStatus.initial,
    this.products = const [],
    this.page = 0,
    this.hasReachedMax = false,
    this.errorMessage,
  });

  final ProductsStatus status;
  final List<Product> products;
  final int page; // highest page loaded (0 before first fetch)
  final bool hasReachedMax;
  final String? errorMessage; // localization key; resets on copyWith

  ProductsState copyWith({
    ProductsStatus? status,
    List<Product>? products,
    int? page,
    bool? hasReachedMax,
    String? errorMessage,
  }) => ProductsState(
    status: status ?? this.status,
    products: products ?? this.products,
    page: page ?? this.page,
    hasReachedMax: hasReachedMax ?? this.hasReachedMax,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => [
    status,
    products,
    page,
    hasReachedMax,
    errorMessage,
  ];
}
