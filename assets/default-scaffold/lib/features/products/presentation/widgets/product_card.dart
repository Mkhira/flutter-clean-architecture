import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:__PKG__/features/products/domain/entities/product.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsetsDirectional.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      child: ListTile(
        leading: CircleAvatar(child: Text('${product.id}')),
        title: Text(product.name, style: textTheme.titleMedium),
        subtitle: Text(product.category.name, style: textTheme.bodySmall),
        trailing: Text(
          '${'products.price'.tr()}: \$${product.price.toStringAsFixed(2)}',
          style: textTheme.labelLarge?.copyWith(color: colorScheme.primary),
        ),
      ),
    );
  }
}
