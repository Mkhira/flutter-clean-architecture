import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:__PKG__/core/error/result.dart';
import 'package:__PKG__/features/products/domain/entities/product.dart';
import 'package:__PKG__/features/products/domain/usecases/get_products_use_case.dart';

part 'products_event.dart';
part 'products_state.dart';

final class ProductsBloc extends Bloc<ProductsEvent, ProductsState> {
  ProductsBloc(this._getProductsUseCase) : super(const ProductsState()) {
    on<ProductsFetched>(_onFetched, transformer: droppable());
    on<ProductsRefreshed>(_onRefreshed, transformer: restartable());
  }

  final GetProductsUseCase _getProductsUseCase;

  Future<void> _onFetched(
    ProductsFetched event,
    Emitter<ProductsState> emit,
  ) async {
    if (state.hasReachedMax) return;
    final result = await _getProductsUseCase(page: state.page + 1);
    switch (result) {
      case Success(:final data):
        emit(
          state.copyWith(
            status: ProductsStatus.success,
            products: [...state.products, ...data.products],
            page: data.page,
            hasReachedMax: data.hasReachedMax,
          ),
        );
      case FailureResult(:final failure):
        emit(
          state.copyWith(
            status: ProductsStatus.failure,
            errorMessage: failure.message,
          ),
        );
    }
  }

  Future<void> _onRefreshed(
    ProductsRefreshed event,
    Emitter<ProductsState> emit,
  ) async {
    final result = await _getProductsUseCase();
    switch (result) {
      case Success(:final data):
        emit(
          ProductsState(
            status: ProductsStatus.success,
            products: data.products,
            page: data.page,
            hasReachedMax: data.hasReachedMax,
          ),
        );
      case FailureResult(:final failure):
        emit(
          state.copyWith(
            status: ProductsStatus.failure,
            errorMessage: failure.message,
          ),
        );
    }
  }
}
