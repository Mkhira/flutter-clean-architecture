# Testing

Required test packages (resolve via `pub add dev:` — see `package-stack.md`):

```yaml
dev_dependencies:
  bloc_test: latest-compatible   # must match installed bloc major
  mocktail: latest-compatible
```

## Test structure

```text
test/
├── core/
└── features/
    └── feature_name/
        ├── data/
        ├── domain/
        └── presentation/
```

## Running tests (keep output small)

- Use the **compact reporter** and **scope to changed tests**:
  `flutter test -r compact test/features/<feature>/...`. The default expanded
  reporter emits a progress line per test (several thousand tokens per run);
  `-r compact` collapses it to one updating line. Run the whole `test/` suite
  (still `-r compact`) only for a final pass, not after every edit.
- `scripts/validate_flutter_project.sh` is quiet on success (one `✓ <step>` line
  per step) and dumps diagnostics only on failure; during iteration scope
  `flutter analyze` to `lib/features/<feature>`, full `lib` only on the final pass.

## Rules

- Use `bloc_test` for Cubit/Bloc emission tests.
- Use `mocktail` for repositories/datasources/storage.
- Use unit tests for use cases and pure mappers.
- Use repository tests for API/error mapping.
- Use widget tests for important UI states.
- Stub HydratedBloc storage in tests.
- Register fallback values for custom mocktail argument matchers.
- Reset GetIt between tests if DI is used.
- Do not add brittle tests only for coverage.

## Example bloc_test — default counter

The simplest case, matching the default `CounterCubit` scaffold (no mocks needed
because it has no dependencies):

```dart
blocTest<CounterCubit, CounterState>(
  'emits incremented count on increment()',
  build: CounterCubit.new,
  act: (cubit) => cubit.increment(),
  expect: () => const [CounterState(count: 1)],
);
```

## Example bloc_test — async with mocks

Matches the flat `Equatable` `LoginState` in `bloc-cubit.md`:

```dart
blocTest<LoginCubit, LoginState>(
  'emits loading then success when login succeeds',
  build: () {
    when(() => loginUseCase(any())).thenAnswer(
      (_) async => const Success(user),
    );
    return LoginCubit(loginUseCase);
  },
  act: (cubit) => cubit.login(email: 'a@b.com', password: 'password'),
  expect: () => const [
    LoginState(isLoading: true),
    LoginState(isSuccess: true),
  ],
);
```

> If the project uses Freezed union states instead, the expectation becomes
> `[LoginState.loading(), LoginState.success(user)]`. Match whichever style the
> feature uses — do not mix styles.

## Example bloc_test — paginated Bloc (droppable)

The default products Bloc uses `droppable()`, which **drops events added while a
handler is still running**. So to test appending a second page, let the first
fetch settle before adding the next event — otherwise the second `ProductsFetched`
is dropped and never runs:

```dart
blocTest<ProductsBloc, ProductsState>(
  'appends the next page and sets hasReachedMax at the end',
  build: () {
    when(() => useCase()).thenAnswer((_) async => Success(page1)); // page 1
    when(() => useCase(page: 2)).thenAnswer((_) async => Success(page2));
    return ProductsBloc(useCase);
  },
  act: (bloc) async {
    bloc.add(const ProductsFetched());
    await Future<void>.delayed(const Duration(milliseconds: 20)); // let it settle
    bloc.add(const ProductsFetched());
  },
  expect: () => [
    ProductsState(status: ProductsStatus.success, products: page1.products, page: 1),
    ProductsState(
      status: ProductsStatus.success,
      products: [...page1.products, ...page2.products],
      page: 2,
      hasReachedMax: true,
    ),
  ],
);
```

`useCase()` (no `page:`) stubs the first call — `page` defaults to 1, so passing
`page: 1` would trip `avoid_redundant_argument_values`.

Test pull-to-refresh with `seed:` to start from a stale multi-page state, then
assert `ProductsRefreshed` replaces it with a fresh page 1:

```dart
blocTest<ProductsBloc, ProductsState>(
  'ProductsRefreshed reloads from page 1 and replaces the list',
  build: () {
    when(() => useCase()).thenAnswer((_) async => Success(page1));
    return ProductsBloc(useCase);
  },
  seed: () => ProductsState(
    status: ProductsStatus.success,
    products: [...page1.products, ...page2.products],
    page: 2,
    hasReachedMax: true,
  ),
  act: (bloc) => bloc.add(const ProductsRefreshed()),
  expect: () => [
    ProductsState(
      status: ProductsStatus.success,
      products: page1.products,
      page: 1,
    ),
  ],
);
```

## HydratedBloc test rule

- Mock `Storage`.
- Stub reads/writes.
- Set `HydratedBloc.storage` in setup.

## Mocktail rule

- Use `registerFallbackValue` for custom argument matchers.
- **Do not mark a class you intend to mock as `final`.** mocktail's mock
  implements the type, and a `final` (or `base`/`sealed`) class cannot be
  implemented outside its library — you get `invalid_use_of_type_outside_library`
  in the test. So:
  - repository/datasource contracts → `abstract interface class` (implementable).
  - use cases → plain `class` (not `final class`), so a cubit/bloc test can mock
    them.

  Example mock of a use case:

  ```dart
  class _MockGetProductsUseCase extends Mock implements GetProductsUseCase {}
  ```

## Repository test — type the `Result` cast, skip default args

A repository test asserts model→entity mapping and error→failure mapping. Two
`very_good_analysis` traps make the obvious version noisy:

- **Type the cast.** `(result as Success).data` is `dynamic`, so every property
  access on it trips `avoid_dynamic_calls`. Cast to the concrete generic:
  `(result as Success<PaginatedProducts>).data` — now `.products.single.name`
  is statically typed.
- **Don't pass args that equal a default.** Building the fixture with
  `ProductsPageModel(page: 1, totalPages: 1, ...)` trips
  `avoid_redundant_argument_values` because those match the model's defaults.
  Omit them (and let `hasReachedMax` fall out of the defaults).

```dart
when(() => dataSource.getProducts(page: 1)).thenAnswer((_) async => pageModel);

final result = await repository.getProducts();

expect(result, isA<Success<PaginatedProducts>>());
final data = (result as Success<PaginatedProducts>).data; // typed, not dynamic
expect(data.products.single.name, 'Product #1');
```

Map a thrown `DioException` to its failure with `thenThrow` + a `RequestOptions`:

```dart
when(() => dataSource.getProducts(page: 1)).thenThrow(
  DioException(
    requestOptions: RequestOptions(path: '/products'),
    type: DioExceptionType.connectionError,
  ),
);
expect((await repository.getProducts()) as FailureResult, isA<FailureResult>());
```

## Golden tests (visual regression)

Goldens catch unintended visual changes — high value in a **theme/design-system
heavy** app, where one token tweak can silently shift every screen. But raw
goldens are notoriously flaky, so adopt them deliberately.

> **Why raw `matchesGoldenFile` goes flaky:** Flutter tests render with a
> placeholder font unless you load real fonts, and anti-aliasing differs across
> OS/CPU — so a golden captured on a Mac fails in Linux CI. Teams then delete the
> goldens. Avoid this by (a) loading fonts in the harness and (b) running goldens
> in **one** controlled environment (CI), not on each dev's machine.

Recommended: **`alchemist`** (dev dep) — it loads app fonts, separates
"CI goldens" from "platform goldens", and disables flaky platform rendering by
default:

```dart
goldenTest(
  'ProductCard renders',
  fileName: 'product_card',
  builder: () => GoldenTestGroup(
    children: [
      GoldenTestScenario(
        name: 'default',
        child: const ProductCard(product: _sampleProduct),
      ),
    ],
  ),
);
```

Plain Flutter alternative (`golden_toolkit` or built-in) — load fonts first:

```dart
testWidgets('login matches golden', (tester) async {
  await loadAppFonts(); // golden_toolkit; without this, text is boxes
  await tester.pumpWidget(/* widget under MaterialApp + theme */);
  await expectLater(
    find.byType(LoginView),
    matchesGoldenFile('goldens/login.png'),
  );
});
```

Rules:
- Update goldens **intentionally** only: `flutter test --update-goldens`, then
  review the image diff before committing. Never blanket-update to make tests pass.
- Commit golden PNGs; generate/refresh them in a single controlled env (CI).
- Wrap the widget in the real `MaterialApp`/theme + localization so the golden
  reflects production styling (see `theme.md`, `localization.md`).
- Keep goldens for stable, high-value surfaces (cards, key pages) — not every
  widget; churny UI produces churny goldens.

## Integration tests (end-to-end)

Use the SDK `integration_test` package for real app flows (login → list → detail)
on a device/emulator — the top of the pyramid, above widget tests.

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

```dart
// integration_test/app_test.dart
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('logs in and reaches the home list', (tester) async {
    await tester.pumpWidget(/* the real App, with fakes/test DI as needed */);
    await tester.pumpAndSettle();
    // enter credentials, tap sign in, expect the gated screen…
  });
}
```

Run: `flutter test integration_test/` (or on a device:
`flutter test integration_test/app_test.dart -d <device>`).

Rules:
- Keep integration tests **few and high-value** (critical journeys) — they are
  slow and need a device/emulator.
- Inject fakes/test doubles for the network at the DI boundary so flows are
  deterministic (reuse the fake-datasource pattern — see `feature-generation.md`).
- Don't run them in the fast unit/widget loop; they're a separate (often CI) job.
