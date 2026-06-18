# GetX (presentation state only)

Load this **instead of** `bloc-cubit.md` when the project's stack is GetX.
Domain and data are **identical** to every other stack (see `architecture.md`).

> **Loud constraint — GetX is used for presentation STATE ONLY.** Use
> `GetxController` + `Obx` for reactive UI. Keep **GetIt** for DI and
> **go_router** for routing. Do **NOT** use `Get.put`/`Get.find`/`Get.lazyPut`
> for repositories/use cases, and do **NOT** use `GetMaterialApp` or GetX
> navigation. This stops GetX from swallowing the architecture; the rest of the
> skill (DI, routing, errors) stays consistent across stacks.

## Role mapping

| Pipeline slot | GetX |
|---|---|
| presentation state | `GetxController` with `.obs` observables |
| rebuild widget | `Obx(() => …)` |
| DI | **GetIt** (controller as a factory) — *not* `Get.put` |
| async + Result | controller method: set `status.obs` → await → `switch(result)` → set observables |
| build_runner | no |
| tests | unit test the controller, assert `.value` (no GetX test utils) |

## Presentation — GetxController + Obx

```dart
// features/items/presentation/controller/items_controller.dart
enum ItemsStatus { initial, loading, success, failure }

class ItemsController extends GetxController {
  ItemsController(this._getItems);

  final GetItemsUseCase _getItems;

  final status = ItemsStatus.initial.obs;
  final items = <Item>[].obs;
  final errorMessage = RxnString();

  Future<void> load() async {
    status.value = ItemsStatus.loading;
    errorMessage.value = null;
    final result = await _getItems();
    switch (result) {
      case Success(:final data):
        items.assignAll(data);
        status.value = ItemsStatus.success;
      case FailureResult(:final failure):
        errorMessage.value = failure.message;
        status.value = ItemsStatus.failure;
    }
  }
}
```

## DI wiring — GetIt, controller held by the widget

The controller is created via GetIt (not `Get.put`) and owned by a
`StatefulWidget`, so `Obx` reacts without GetX's binding/lifecycle.

```dart
// core/di/injection.dart
getIt
  ..registerLazySingleton(() => GetItemsUseCase(getIt<ItemsRepository>()))
  ..registerFactory(() => ItemsController(getIt<GetItemsUseCase>()));
```

```dart
// features/items/presentation/pages/items_page.dart
class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  late final ItemsController _c = getIt<ItemsController>()..load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('items.title'.tr())),
      body: Obx(() {
        switch (_c.status.value) {
          case ItemsStatus.initial:
          case ItemsStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case ItemsStatus.failure:
            return Center(
              child: Text((_c.errorMessage.value ?? 'common.unknown_error').tr()),
            );
          case ItemsStatus.success:
            return ListView.builder(
              itemCount: _c.items.length,
              itemBuilder: (context, i) =>
                  ListTile(title: Text('#${_c.items[i].id}')),
            );
        }
      }),
    );
  }
}
```

> Since the controller is not managed by GetX's lifecycle, avoid GetX *workers*
> (`ever`/`debounce`) that need disposal — or cancel them in `State.dispose`.
> Plain `.obs` fields need no disposal.

## Tests

```dart
class _MockGetItemsUseCase extends Mock implements GetItemsUseCase {}

test('controller loads items on success', () async {
  final useCase = _MockGetItemsUseCase();
  when(() => useCase()).thenAnswer((_) async => const Success(<Item>[]));

  final c = ItemsController(useCase);
  await c.load();

  expect(c.status.value, ItemsStatus.success);
  expect(c.items, isEmpty);
});
```

## Rules

- GetX = **state only**. GetIt for DI, go_router for routing — never `Get.put`/
  `GetMaterialApp`.
- `Obx` must read at least one `.obs` value in its builder to react.
- Repository still maps `DioException → AppFailure`; the controller stores the key.
- Persisted settings use `shared_preferences` (not GetStorage — stay off GetX
  subsystems).
