part of 'products_bloc.dart';

sealed class ProductsEvent extends Equatable {
  const ProductsEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load and every scroll-to-bottom both dispatch this; the Bloc
/// derives the next page number from the current state.
final class ProductsFetched extends ProductsEvent {
  const ProductsFetched();
}

/// Pull-to-refresh: reload from page 1, replacing the current list.
final class ProductsRefreshed extends ProductsEvent {
  const ProductsRefreshed();
}
