import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:__PKG__/core/di/injection.dart';
import 'package:__PKG__/features/products/presentation/bloc/products_bloc.dart';
import 'package:__PKG__/features/products/presentation/widgets/product_card.dart';
import 'package:__PKG__/features/settings/presentation/widgets/language_toggle_button.dart';
import 'package:__PKG__/features/settings/presentation/widgets/theme_mode_toggle_button.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ProductsBloc>()..add(const ProductsFetched()),
      child: const ProductsView(),
    );
  }
}

class ProductsView extends StatefulWidget {
  const ProductsView({super.key});

  @override
  State<ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends State<ProductsView> {
  final ScrollController _scrollController = ScrollController();
  bool _wasNearBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return false;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    return current >= max * 0.9;
  }

  void _onScroll() {
    final nearBottom = _isNearBottom;
    if (nearBottom && !_wasNearBottom) {
      context.read<ProductsBloc>().add(const ProductsFetched());
    }
    _wasNearBottom = nearBottom;
  }

  Future<void> _onRefresh() async {
    final bloc = context.read<ProductsBloc>()..add(const ProductsRefreshed());
    await bloc.stream.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('products.title'.tr()),
        actions: const [
          LanguageToggleButton(),
          ThemeModeToggleButton(),
          SizedBox(width: 8),
        ],
      ),
      body: BlocBuilder<ProductsBloc, ProductsState>(
        builder: (context, state) {
          if (state.status == ProductsStatus.failure &&
              state.products.isEmpty) {
            return _ErrorView(
              messageKey: state.errorMessage ?? 'common.unknown_error',
              onRetry: () =>
                  context.read<ProductsBloc>().add(const ProductsFetched()),
            );
          }
          if (state.status == ProductsStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.products.isEmpty) {
            return Center(child: Text('products.empty'.tr()));
          }
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.hasReachedMax
                  ? state.products.length
                  : state.products.length + 1,
              itemBuilder: (context, index) {
                if (index >= state.products.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ProductCard(product: state.products[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.messageKey, required this.onRetry});

  final String messageKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(messageKey.tr()),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            child: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }
}
