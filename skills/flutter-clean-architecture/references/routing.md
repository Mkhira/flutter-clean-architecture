# Routing

Default new-project recommendation:

```yaml
go_router: latest-compatible
```

## Rules

- In existing projects, keep the existing router unless asked to migrate.
- Place router config under `core/router/`.
- Routes should not construct heavy dependencies manually; use DI/BlocProvider.
- Use route guards/redirects for auth when appropriate.
- Localized routes are optional; do not invent them.

## Example

New projects point the default route at the products feature's `ProductsPage`
(the default full-stack example — see `project-creation.md`); swap in your real
landing page as the app grows.

```dart
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ProductsPage(),
    ),
  ],
);
```

`MaterialApp.router` must include localization delegates from easy_localization:

```dart
MaterialApp.router(
  routerConfig: router,
  localizationsDelegates: context.localizationDelegates,
  supportedLocales: context.supportedLocales,
  locale: context.locale,
)
```

## Auth-gated navigation (the part most apps actually need)

Scaffolding token storage (`auth-and-secure-storage.md`) is only half the job —
the router has to *gate* screens on auth state. Two pieces do this:

- **`redirect`** decides, on every navigation, whether the user may see the
  target — bounce unauthenticated users to `/login`, and bounce authenticated
  users away from `/login`.
- **`refreshListenable`** re-runs `redirect` the moment auth state changes (login,
  logout, token expiry) — without it, the redirect only evaluates on manual
  navigation and the UI goes stale.

Bridge the auth Bloc's *stream* to a `Listenable` (go_router listens to
`ChangeNotifier`, Bloc exposes a `Stream`):

```dart
/// Adapts a Stream (e.g. AuthBloc.stream) into a Listenable for go_router.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

```dart
GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final loggedIn = authBloc.state.isAuthenticated;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null; // no redirect
    },
    routes: [/* ... */],
  );
}
```

Build the router from DI so it gets the same `AuthBloc` singleton:
`getIt.registerLazySingleton(() => createRouter(getIt<AuthBloc>()))`. Keep auth
*state* in the Bloc; the router only *reads* it — no auth logic in the router.

## ShellRoute — persistent bottom nav / shared scaffold

Use `ShellRoute` (or `StatefulShellRoute.indexedStack` to keep each tab's state)
when several routes share a chrome like a `BottomNavigationBar`:

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      ScaffoldWithNavBar(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(routes: [GoRoute(path: '/home', builder: ...)]),
    StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: ...)]),
  ],
)
```

## Deep links

go_router handles incoming deep links through the same route table, so a
well-formed `routes` tree mostly "just works". The platform pieces still need
declaring: Android `<intent-filter>` (App Links) in `AndroidManifest.xml`, iOS
Associated Domains / `CFBundleURLTypes`. The `redirect` guard above applies to
deep links too — an unauthenticated deep link into `/orders/42` is bounced to
`/login` automatically. Preserve the original target (e.g. via a `from` query
param) if you want to resume after login.

## Typed routes (optional)

`@TypedGoRoute<...>` generates type-safe route classes so args aren't
stringly-typed (`const OrderRoute(id: 42).go(context)` instead of
`context.go('/orders/42')`). It is **opt-in**: it adds another `build_runner`
generator, so only reach for it when route args are non-trivial or numerous —
otherwise plain path routes keep the stack leaner.
