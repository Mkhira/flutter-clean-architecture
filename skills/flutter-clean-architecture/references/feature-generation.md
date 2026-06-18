# Feature Generation

## Scaffold the skeleton first (token-saver)

Don't hand-emit the mechanical boilerplate (folder tree, import lines, `part`
directives, empty bloc/cubit/state shells) as output tokens — run the generator
and spend tokens only on the parts that carry real logic (the mapper body, the
use-case logic, the event/cubit handlers, the real model fields):

```bash
scripts/new_feature.sh <ui|api|form> <feature_name> [--item <singular>]
```

- `ui`   — presentation-only page (no domain/data — nothing to abstract).
- `api`  — full clean arch: domain (entity/repo/use case) + data
  (model/datasource/repo impl, error→failure mapping) + presentation (Cubit + page).
- `form` — presentation Cubit + a validated `Form` page (wire a use case into
  `submit()`).

**Collection-named features:** when the feature name is plural, pass `--item`
so the entity/model are singular while the collection types stay plural:

```bash
scripts/new_feature.sh api elixirs --item elixir
#  -> entity Elixir, model ElixirModel (files elixir.dart, elixir_model.dart)
#  -> ElixirsRepository, GetElixirsUseCase, ElixirsCubit, ElixirsPage
```

It refuses to overwrite an existing feature, emits analyze-clean skeletons with
`TODO(you):` markers, and prints the exact DI / build_runner / localization
follow-ups. After scaffolding, fill the logic, then run build_runner (for `api`
models), `scripts/check_layers.sh`, format, and `flutter analyze`. The generator
respects the layering below — it never creates empty layers (UI-only has no
domain/data).

**Trust the FINAL list** the generator prints: those files carry no `TODO(you)`,
are complete and analyze-clean — do not open them. Locate remaining work with
`grep -rln 'TODO(you)' lib/features/<name>`, not by reading files to look.

### Generate the data shape from a sample — `--json`

For `api` features, pass a sample response and the generator infers the **entity
+ model + nested types + `toEntity` mapping** instead of a single-`id` stub:

```bash
scripts/new_feature.sh api houses --item house --json houses_sample.json
#  -> House + nested HouseHead/HouseTrait entities
#  -> HouseModel + HouseHeadModel + HouseTraitModel (with fromJson + toEntity)
```

How it infers (it MERGES all records in the sample, so a field null/absent in
any record is treated nullable):

- scalar → `String`/`int`/`double`/`bool`; object → nested model; array of
  objects → `List<NestedModel>` (named `<Item><SingularKey>`, e.g. `heads` →
  `HouseHead`).
- **Models default every field nullable** (APIs lie even when the sample is
  full); **entities are non-null with fallbacks** (`?? ''`). `id` is kept
  required.
- snake_case keys get `@JsonKey(name: '...')` automatically.

Review the output (~30s) — single-sample inference is heuristic for
**`int` vs `double`**, **nullability**, and `null`/empty-array fields (emitted as
`Object?` with a `TODO(you):`). And it does **not** write the Retrofit client —
the verb/path/envelope aren't in a data sample, so that one file stays manual
(see `networking.md`). Without `--json` it emits the single-`id` stub for you to
fill by hand.

### Generate from a contract — `--openapi` (preferred when a spec exists)

If the API publishes an OpenAPI / Swagger spec, pass the **spec file** plus the
endpoint. Unlike `--json` (one sample, heuristic, no client), the spec is a
contract — so the generator emits **exact** types **and the Retrofit client**:

```bash
scripts/new_feature.sh api elixirs --item elixir \
  --openapi swagger.json --path /Elixirs [--method get]
#  -> Elixir (+ nested entities from $ref schemas; enums as String)
#  -> ElixirModel (+ nested models, fromJson + toEntity)
#  -> ElixirsApi  (@RestApi, @GET('/Elixirs') -> List<ElixirModel>)
#  -> ElixirsRemoteDataSourceImpl(Dio dio)  wired to the client
```

What the spec gives over a sample: definitive **`int` vs `double`**, real
**nullability** (`nullable` / `required`), `format: date-time`/`date` →
**`DateTime`** (nullable in the entity), nested `$ref` objects (named after the
schema, `…Dto`/`…Model` suffix stripped), **enums** (mapped to `String`), and the
**endpoint** — so the Retrofit client and a Dio-backed datasource are generated,
not hand-written. Set the Dio `baseUrl` where you register/construct it; for
Riverpod the generated datasource provider is patched to take a `Dio`.
`--openapi` and `--json` are mutually exclusive.

**Methods:**

- `--method get` (default) — two shapes, auto-detected:
  - **collection** (array response): entity/model (+nested) + `@GET → List<Model>`
    + `fetchAll` datasource, repo, use case. Any **query parameters** become
    optional named `@Query` filters threaded through datasource → repo → use case.
    Branches presentation per `--stack` (the list screen).
  - **fetch-by-id** (path has `{id}` and the response is a single object): client
    `@GET('/x/{id}') → Model` with `@Path`, a `fetchOne`/`getById` chain, a
    `Get…ByIdUseCase`, and a **detail** holder (per `--stack`) whose page takes
    the `id` and loads on open.
- `--method post|put|patch|delete` — a **command**. From the operation it reads
  **path parameters** (`/things/{id}` → `@Path('id')`) and the `requestBody`
  schema → request entity + model (`toJson` + `fromEntity`), the verb-correct
  Retrofit client (`@POST`/`@PUT`/`@PATCH`/`@DELETE`, with `@Path`/`@Body` as
  needed), a Dio-backed datasource, and the repo + use case
  (`submit`/`update`/`patch`/`delete`, `Submit…`/`Update…`/… use case). A 2xx
  response body → `Result<Entity>`; **no body → `Result<bool>`** (DELETE/204).
  A **command** holder is generated for the active `--stack` (a submit-button
  stub to wire to your form/action). Command + fetch-by-id presentation is
  generated for **all five stacks** (Bloc/Riverpod/Provider/GetX/MobX). Command
  verbs require `--openapi`.

## Workflow

1. Understand the feature behavior and its UX/API requirements.
2. Inspect existing folder conventions.
3. Decide what kind of feature it is:
   - UI-only
   - local state
   - API-backed
   - authenticated
   - persisted
   - form-heavy
4. Scaffold the skeleton with `scripts/new_feature.sh` (above), then create only
   the necessary additional layers by hand.
5. Add tests appropriate to the behavior.
6. Validate.

## Default feature structure

The per-feature folder tree is single-sourced in `architecture.md` (Folder
layout). Do not create empty folders. Use Cubit for straightforward
commands/states; use Bloc for event-heavy flows (see `bloc-cubit.md`).

### Example UI-only feature

```text
lib/features/about/presentation/pages/about_page.dart
lib/features/about/presentation/widgets/
```

### Example local-state feature (the default counter)

Local UI state managed by a Cubit — still presentation-only, because there is
no API/repository/use case to abstract. This is exactly the default `counter`
scaffold new projects ship (see `bloc-cubit.md`):

```text
lib/features/counter/presentation/cubit/counter_cubit.dart
lib/features/counter/presentation/cubit/counter_state.dart
lib/features/counter/presentation/pages/counter_page.dart
```

Do not add `domain/` or `data/` folders here — a counter has no boundary to
abstract, and empty layers are the architecture theater the skill avoids.

### Example API feature

```text
domain/entities/
domain/repositories/
domain/usecases/
data/models/
data/datasources/
data/repositories/
presentation/cubit/
presentation/pages/
```

### Extended example — products (paginated API feature)

```text
lib/features/products/
├── data/
│   ├── api/products_api_client.dart          # @RestApi Retrofit interface
│   ├── datasources/
│   │   ├── products_remote_data_source.dart       # contract + Retrofit impl
│   │   └── products_fake_remote_data_source.dart  # seeded, paginated sample data
│   ├── models/
│   │   ├── products_page_model.dart           # page envelope: {items, page, pageSize, total, totalPages}
│   │   ├── product_model.dart                 # @JsonSerializable item
│   │   └── product_category_model.dart        # nested object
│   └── repositories/products_repository_impl.dart   # model→entity, error→failure
├── domain/
│   ├── entities/product.dart
│   ├── entities/product_category.dart
│   ├── entities/paginated_products.dart       # items + page/totalPages + hasReachedMax
│   ├── repositories/products_repository.dart
│   └── usecases/get_products_use_case.dart
└── presentation/
    ├── bloc/
    │   ├── products_bloc.dart                 # Bloc (event-heavy: pagination)
    │   ├── products_event.dart
    │   └── products_state.dart
    ├── pages/products_page.dart               # infinite scroll
    └── widgets/product_card.dart
```

The `@RestApi` Retrofit client lives in its own `data/api/` file (see
`networking.md`); the datasource calls it and unwraps the response envelope.
Model nested objects (like `category`) and the response envelope each get their
own model when meaningful — never use `List<dynamic>` at the data boundary.

This feature uses a **Bloc**, not a Cubit, because the flow is event-heavy:
every scroll-to-bottom dispatches a fetch and pagination needs `droppable()` to
ignore overlapping requests (see `bloc-cubit.md`). Pagination metadata lives in
the `PaginatedProducts` domain entity so the Bloc can decide `hasReachedMax`.

## Naming rules

- snake_case for folders and files.
- PascalCase for classes.
- Clear domain names.
- Do not use generic names like `Data`, `Manager`, or `Helper` unless
  unavoidable.

## Implementation flow

- UI sends user intent to Cubit/Bloc.
- Cubit/Bloc calls a use case or repository.
- Use case calls the repository contract.
- Repository implementation calls the datasource.
- Datasource calls the API/cache.
- Models map to domain entities.
- Failures/results travel back upward.

## Fake / in-memory datasource (default example & offline dev)

A datasource is just an implementation of its contract, so you can ship a
**fake** alongside the real one and choose between them in DI. This is how the
default **products** feature displays data with no backend, and it's a clean way
to develop UI before an API exists:

The default products feature is **paginated**, so the fake synthesizes a
catalogue and serves it a page at a time — giving the infinite-scroll Bloc real
pages to fetch with no backend. It returns the **same `ProductsPageModel`** the
Retrofit-backed datasource returns:

```dart
// data/datasources/products_fake_remote_data_source.dart
final class ProductsFakeRemoteDataSource implements ProductsRemoteDataSource {
  const ProductsFakeRemoteDataSource();

  static const int _total = 25;
  static const int _pageSize = 10;

  @override
  Future<ProductsPageModel> getProducts({int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600)); // latency
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize) > _total ? _total : start + _pageSize;
    final items = <ProductModel>[
      for (var id = start + 1; id <= end; id++) _buildProduct(id),
    ];
    return ProductsPageModel(
      items: items,
      page: page,
      pageSize: _pageSize,
      total: _total,
      totalPages: (_total / _pageSize).ceil(),
    );
  }

  ProductModel _buildProduct(int id) { /* deterministic sample item */ }
}
```

Select the implementation in one DI line (the DIP payoff — nothing upstream
changes):

```dart
// Default example / offline: seeded, paginated data.
..registerLazySingleton<ProductsRemoteDataSource>(
  () => const ProductsFakeRemoteDataSource(),
)
// Real backend: swap the line above for this once the API is ready.
//   () => ProductsRemoteDataSourceImpl(getIt<ProductsApiClient>()),
```

The fake returns the **same type** the real datasource returns, so the
repository, use case, Bloc, and UI are identical for both. Keep the seed data
realistic (derived from the real response JSON). Do not branch on "is fake"
anywhere above the datasource.

## Class modifiers and mockability

A class that gets mocked in tests must be implementable, so **do not mark it
`final`** (or `base`/`sealed`):

- Repository and datasource **contracts** → `abstract interface class`.
- **Use cases** → plain `class` (not `final class`) — cubit/bloc tests mock them.
- Repository/datasource **implementations** that are only constructed (never
  mocked) may be `final class`.
- Entities and states stay `final class … extends Equatable` (they are compared,
  not mocked).

Marking a mocked type `final` causes `invalid_use_of_type_outside_library` in the
test file (see `testing.md`).
