# Riverpod (presentation + DI)

Load this **instead of** `bloc-cubit.md` when the project's stack is Riverpod.
Domain and data are **identical** to every other stack (see `architecture.md`):
entities, repository contracts, use cases, models, datasources, mappers, and the
`Result`/`AppFailure` flow do not change. Only the presentation layer **and the
DI mechanism** change — in Riverpod, **providers ARE the DI** (no GetIt).

## Role mapping

| Pipeline slot | Riverpod |
|---|---|
| presentation state | `@riverpod` `AsyncNotifier` (or `Notifier`) |
| rebuild widget | `ConsumerWidget` + `ref.watch(...)`; `ref.listen` for effects |
| DI | provider graph (`ProviderScope` root) — **no get_it** |
| async + Result | `build()`/action returns data; `Success→data`, `FailureResult→throw failure` (→ `AsyncError`) |
| build_runner | **yes** (riverpod_generator) |
| tests | `ProviderContainer` + `overrideWith` + mocktail |

## DI = providers (replaces core/di/injection.dart)

The composition root is the provider graph + `ProviderScope`. Each layer is a
provider; tests override the leaf.

```dart
// core/di/providers.dart
part 'providers.g.dart';

@riverpod
Dio dio(Ref ref) => createDio(baseUrl: Env.baseUrl);

@riverpod
ItemsRemoteDataSource itemsRemoteDataSource(Ref ref) =>
    ItemsRemoteDataSourceImpl(ref.watch(dioProvider));

@riverpod
ItemsRepository itemsRepository(Ref ref) =>
    ItemsRepositoryImpl(ref.watch(itemsRemoteDataSourceProvider));

@riverpod
GetItemsUseCase getItemsUseCase(Ref ref) =>
    GetItemsUseCase(ref.watch(itemsRepositoryProvider));
```

```dart
// main.dart — wrap the app once
runApp(const ProviderScope(child: App()));
```

## Presentation — AsyncNotifier + ConsumerWidget

```dart
// features/items/presentation/notifier/items_notifier.dart
part 'items_notifier.g.dart';

@riverpod
class Items extends _$Items {
  @override
  Future<List<Item>> build() => _fetch();

  Future<List<Item>> _fetch() async {
    final result = await ref.read(getItemsUseCaseProvider)();
    return switch (result) {
      Success(:final data) => data,
      // The repo already mapped Dio → AppFailure; surface it via AsyncError.
      FailureResult(:final failure) => throw failure,
    };
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}
```

```dart
// features/items/presentation/pages/items_page.dart
class ItemsPage extends ConsumerWidget {
  const ItemsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('items.title'.tr())),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text((e is AppFailure ? e.message : 'common.unknown_error').tr()),
        ),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => ListTile(title: Text('#${list[i].id}')),
        ),
      ),
    );
  }
}
```

## Tests — ProviderContainer + overrides (no bloc_test)

```dart
class _MockGetItemsUseCase extends Mock implements GetItemsUseCase {}

test('items provider exposes data on success', () async {
  final useCase = _MockGetItemsUseCase();
  when(() => useCase()).thenAnswer((_) async => const Success(<Item>[]));

  final container = ProviderContainer(
    overrides: [getItemsUseCaseProvider.overrideWithValue(useCase)],
  );
  addTearDown(container.dispose);

  await container.read(itemsProvider.future);
  expect(container.read(itemsProvider).hasValue, isTrue);
});
```

## Rules

- **No `get_it`.** Providers are the DI; override them in tests instead of
  resetting a locator.
- Repositories still map `DioException → AppFailure` (shared, unchanged). The
  notifier only translates `Result` → `AsyncValue` (throw the failure for
  `AsyncError`); never let `DioException` reach the widget.
- Run build_runner after editing `@riverpod` classes/providers (see
  `models-and-codegen.md` / `codegen-troubleshooting.md`).
- Use `ref.watch` to rebuild, `ref.read` inside callbacks/actions, `ref.listen`
  for one-off effects (snackbars/navigation).
- Persisted settings (locale/theme) use `shared_preferences` (no HydratedBloc):
  a `Notifier` that loads in `build()` and writes on change.
