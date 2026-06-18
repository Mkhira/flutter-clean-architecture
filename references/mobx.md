# MobX (presentation)

Load this **instead of** `bloc-cubit.md` when the project's stack is MobX.
Domain and data are **identical** to every other stack (see `architecture.md`).
MobX ships no DI, so this skill **adds `get_it`** for DI (consistent with the
rest of the stack) — document that in the project.

## Role mapping

| Pipeline slot | MobX |
|---|---|
| presentation state | `Store` (`with Store`, `@observable`/`@action`) |
| rebuild widget | `Observer(builder: …)` |
| DI | **GetIt** (added — store as a factory) |
| async + Result | `@action`: set observable → await → `switch(result)` → set observables |
| build_runner | **yes** (mobx_codegen → `*_store.g.dart`) |
| tests | unit test the store, assert observables |

## Presentation — MobX Store

```dart
// features/items/presentation/store/items_store.dart
part 'items_store.g.dart';

enum ItemsStatus { initial, loading, success, failure }

class ItemsStore = _ItemsStore with _$ItemsStore;

abstract class _ItemsStore with Store {
  _ItemsStore(this._getItems);

  final GetItemsUseCase _getItems;

  @observable
  ItemsStatus status = ItemsStatus.initial;

  @observable
  ObservableList<Item> items = ObservableList<Item>();

  @observable
  String? errorMessage;

  @action
  Future<void> load() async {
    status = ItemsStatus.loading;
    errorMessage = null;
    final result = await _getItems();
    switch (result) {
      case Success(:final data):
        items = ObservableList.of(data);
        status = ItemsStatus.success;
      case FailureResult(:final failure):
        errorMessage = failure.message;
        status = ItemsStatus.failure;
    }
  }
}
```

## DI wiring — GetIt, store held by the widget

```dart
// core/di/injection.dart
getIt
  ..registerLazySingleton(() => GetItemsUseCase(getIt<ItemsRepository>()))
  ..registerFactory(() => ItemsStore(getIt<GetItemsUseCase>()));
```

```dart
// features/items/presentation/pages/items_page.dart
class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  late final ItemsStore _store = getIt<ItemsStore>()..load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('items.title'.tr())),
      body: Observer(
        builder: (context) {
          switch (_store.status) {
            case ItemsStatus.initial:
            case ItemsStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case ItemsStatus.failure:
              return Center(
                child: Text((_store.errorMessage ?? 'common.unknown_error').tr()),
              );
            case ItemsStatus.success:
              return ListView.builder(
                itemCount: _store.items.length,
                itemBuilder: (context, i) =>
                    ListTile(title: Text('#${_store.items[i].id}')),
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

test('store loads items on success', () async {
  final useCase = _MockGetItemsUseCase();
  when(() => useCase()).thenAnswer((_) async => const Success(<Item>[]));

  final store = ItemsStore(useCase);
  await store.load();

  expect(store.status, ItemsStatus.success);
  expect(store.items, isEmpty);
});
```

## Rules

- Add **get_it** for DI (MobX has none); store registered as a factory.
- Mutate observables only inside `@action`; wrap reactive UI in `Observer`.
- Run build_runner after editing a store (`*_store.g.dart`); the `part` directive
  is already detected by `validate_flutter_project.sh` / `doctor.sh`.
- Repository still maps `DioException → AppFailure`; the store stores the key.
- Persisted settings use `shared_preferences`.
