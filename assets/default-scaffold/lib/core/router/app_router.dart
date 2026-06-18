import 'package:go_router/go_router.dart';
import 'package:__PKG__/features/products/presentation/pages/products_page.dart';

/// App router. The default route renders the products feature — swap in your
/// real landing page as the app grows.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ProductsPage(),
    ),
  ],
);
