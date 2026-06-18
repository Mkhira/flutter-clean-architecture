# Provider (presentation)

Load this **instead of** `bloc-cubit.md` when the project's stack is Provider.
Domain and data are **identical** to every other stack (see `architecture.md`).
Only presentation changes; **DI stays GetIt** (the `provider` package propagates
state, it is not a DI container for repositories/use cases).

## Role mapping

| Pipeline slot | Provider |
|---|---|
| presentation state | `ChangeNotifier` |
| rebuild widget | `ChangeNotifierProvider` + `Consumer`/`context.watch` |
| DI | **GetIt** (repo/usecase + the notifier as a factory) |
| async + Result | method: set loading → await → `switch(result)` → set fields → `notifyListeners()` |
| build_runner | no |
| tests | unit test the notifier with a mocked use case (no special tooling) |

## Presentation — ChangeNotifier

Mirror the Bloc state as plain fields; `errorMessage` is a localization key and
resets on each load so stale errors don't linger.

```dart
// features/items/presentation/notifier/items_notifier.dart
enum ItemsStatus { initial, loading, success, failure }

class ItemsNotifier extends ChangeNotifier {
  ItemsNotifier(this._getItems);

  final GetItemsUseCase _getItems;

  ItemsStatus status = ItemsStatus.initial;
  List<Item> items = const [];
  String? errorMessage;

  Future<void> load() async {
    status = ItemsStatus.loading;
    errorMessage = null;
    notifyListeners();

    final result = await _getItems();
    switch (result) {
      case Success(:final data):
        items = data;
        status = ItemsStatus.success;
      case FailureResult(:final failure):
        errorMessage = failure.message;
        status = ItemsStatus.failure;
    }
    notifyListeners();
  }
}
```

## DI wiring — GetIt + ChangeNotifierProvider

```dart
// core/di/injection.dart (same pattern as Bloc, notifier as factory)
getIt
  ..registerLazySingleton<ItemsRepository>(
    () => ItemsRepositoryImpl(getIt<ItemsRemoteDataSource>()),
  )
  ..registerLazySingleton(() => GetItemsUseCase(getIt<ItemsRepository>()))
  ..registerFactory(() => ItemsNotifier(getIt<GetItemsUseCase>()));
```

```dart
// features/items/presentation/pages/items_page.dart
class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => getIt<ItemsNotifier>()..load(),
      child: const ItemsView(),
    );
  }
}

class ItemsView extends StatelessWidget {
  const ItemsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('items.title'.tr())),
      body: Consumer<ItemsNotifier>(
        builder: (context, n, _) {
          switch (n.status) {
            case ItemsStatus.initial:
            case ItemsStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case ItemsStatus.failure:
              return Center(
                child: Text((n.errorMessage ?? 'common.unknown_error').tr()),
              );
            case ItemsStatus.success:
              return ListView.builder(
                itemCount: n.items.length,
                itemBuilder: (context, i) => ListTile(title: Text('#${n.items[i].id}')),
              );
          }
        },
      ),
    );
  }
}
```

## Tests

```dart
class _MockGetItemsUseCase extends Mock implements GetItemsUseCase {}

test('notifier emits success then exposes items', () async {
  final useCase = _MockGetItemsUseCase();
  when(() => useCase()).thenAnswer((_) async => const Success(<Item>[]));

  final notifier = ItemsNotifier(useCase);
  await notifier.load();

  expect(notifier.status, ItemsStatus.success);
  expect(notifier.items, isEmpty);
});
```

## Rules

- DI is **GetIt**, not `provider` — register repos/use cases/notifiers there; use
  `ChangeNotifierProvider`/`Consumer` only to expose the notifier to the tree.
- Use `context.select`/`Consumer` with a tight scope to avoid rebuilding the
  whole subtree.
- `notifyListeners()` after every state mutation; reset `errorMessage` on load.
- Repository still maps `DioException → AppFailure`; the notifier only stores the
  resulting key.
- Persisted settings use `shared_preferences`.
