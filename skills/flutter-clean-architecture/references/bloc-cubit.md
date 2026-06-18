# Bloc / Cubit

## Rules

- Prefer Cubit for simple state transitions.
- Use Bloc when there are events, debounce, cancellation, restartable searches,
  sequential writes, droppable button taps, or multiple event sources.
- Keep Cubit/Bloc free of widget code.
- Cubit/Bloc may call use cases or repositories.
- UI reacts to state and sends user intentions.
- Use immutable states.
- Use `Equatable` by default for state equality.
- Use `Freezed` for complex union states when available/appropriate.

> **State-style consistency:** the examples in this skill use the flat
> `Equatable` state style by default (boolean/nullable fields + `copyWith`). If a
> project uses Freezed union states (`State.loading()`, `State.success(data)`),
> adapt all examples (including the tests in `testing.md`) to that style. Do not
> mix the two styles within one feature.

## Bloc concurrency

- `restartable()` for search/autocomplete/latest-only requests, and for
  pull-to-refresh (a new refresh supersedes any in-flight one).
- `droppable()` for submit buttons where repeated taps should be ignored, and
  for scroll-triggered pagination (ignore overlapping load-more fetches).
- `sequential()` for writes that must happen in order.
- `concurrent()` only when parallel handling is safe.

## Flutter Bloc widgets

- `BlocBuilder` for rendering.
- `BlocListener` for one-time effects like navigation/snackbars/dialogs.
- `BlocConsumer` only when both building and listening are needed.
- `BlocSelector` or `context.select` for fine-grained rebuilds.
- `BlocProvider.value` only for existing bloc instances passed to new routes.

## HydratedBloc

- Use for small persisted app state like theme, locale, onboarding, filters.
- Do not use for secure tokens.
- Do not use as a database.
- Override `storagePrefix` for production stability when needed.
- Stub storage in tests.

## App-level observer

`lib/app/app_bloc_observer.dart`:

```dart
class AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    // Log only in debug/dev. Never log secrets/tokens.
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    // Log only in debug/dev.
    super.onError(bloc, error, stackTrace);
  }
}
```

Keep the observer light — diagnostics/logging only, never business logic.

## Minimal local-state Cubit (counter example)

The smallest honest demonstration of Cubit in this architecture. The default
landing feature for new projects is **products** (the full data/domain/
presentation example — see `project-creation.md` and `feature-generation.md`);
this counter stays here as the minimal reference. A counter is *local UI state*:
it has **no domain or data layer**, because there is nothing to abstract (no API,
no repository, no use case). Creating those layers for a counter would be
architecture theater (see `architecture.md`). The feature is therefore
presentation-only:

```text
lib/features/counter/
└── presentation/
    ├── cubit/
    │   ├── counter_cubit.dart
    │   └── counter_state.dart
    └── pages/
        └── counter_page.dart
```

State (flat `Equatable` style, consistent with the rest of this skill):

```dart
// counter_state.dart
part of 'counter_cubit.dart';

final class CounterState extends Equatable {
  const CounterState({this.count = 0});

  final int count;

  CounterState copyWith({int? count}) =>
      CounterState(count: count ?? this.count);

  @override
  List<Object?> get props => [count];
}
```

Cubit (pure coordination, no widget code, no dependencies):

```dart
// counter_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'counter_state.dart';

final class CounterCubit extends Cubit<CounterState> {
  CounterCubit() : super(const CounterState());

  void increment() => emit(state.copyWith(count: state.count + 1));
  void decrement() => emit(state.copyWith(count: state.count - 1));
}
```

Page — resolve the cubit from DI at the composition boundary, then render with
`BlocBuilder`. The UI only sends intent (`increment`/`decrement`); it holds no
business logic:

```dart
// counter_page.dart
class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CounterCubit>(),
      child: const CounterView(),
    );
  }
}

class CounterView extends StatelessWidget {
  const CounterView({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('counter.title'.tr())),
      body: Center(
        child: BlocBuilder<CounterCubit, CounterState>(
          builder: (context, state) =>
              Text('${state.count}', style: textTheme.displayMedium),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'increment',
            onPressed: () => context.read<CounterCubit>().increment(),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'decrement',
            onPressed: () => context.read<CounterCubit>().decrement(),
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }
}
```

Register the cubit as a factory in DI (`core/di/`):

```dart
getIt.registerFactory(CounterCubit.new);
```

The pattern every feature replicates: DI factory → `BlocProvider` at the
boundary → `BlocBuilder` to render → localized strings → theme text styles. (The
default `/` route renders the products feature, not this counter — see
`project-creation.md`.)

## Paginated list Bloc (default products feature)

The default **products** feature is a paginated, infinite-scroll list — the
canonical reason to choose **Bloc over Cubit**: it is event-driven, and each
scroll-to-bottom must not fire overlapping requests. Use a single
`ProductsFetched` event with the `droppable()` transformer so a new fetch is
ignored while one is in flight; the Bloc derives the next page from state.

Pagination metadata is a domain entity:

```dart
final class PaginatedProducts extends Equatable {
  const PaginatedProducts({
    required this.products,
    required this.page,
    required this.totalPages,
  });

  final List<Product> products;
  final int page;
  final int totalPages;

  bool get hasReachedMax => page >= totalPages;

  @override
  List<Object?> get props => [products, page, totalPages];
}
```

Event + state (flat `Equatable`, `part` files of the bloc):

```dart
// products_event.dart
sealed class ProductsEvent extends Equatable {
  const ProductsEvent();
  @override
  List<Object?> get props => [];
}

/// Initial load and every scroll-to-bottom both dispatch this; the Bloc derives
/// the page number from the current state.
final class ProductsFetched extends ProductsEvent {
  const ProductsFetched();
}

/// Pull-to-refresh: reload from page 1, replacing the current list.
final class ProductsRefreshed extends ProductsEvent {
  const ProductsRefreshed();
}

// products_state.dart
enum ProductsStatus { initial, success, failure }

final class ProductsState extends Equatable {
  const ProductsState({
    this.status = ProductsStatus.initial,
    this.products = const [],
    this.page = 0,
    this.hasReachedMax = false,
    this.errorMessage,
  });

  final ProductsStatus status;
  final List<Product> products;
  final int page; // highest page loaded (0 before first fetch)
  final bool hasReachedMax;
  final String? errorMessage; // localization key; resets on copyWith

  ProductsState copyWith({
    ProductsStatus? status,
    List<Product>? products,
    int? page,
    bool? hasReachedMax,
    String? errorMessage,
  }) => ProductsState(
        status: status ?? this.status,
        products: products ?? this.products,
        page: page ?? this.page,
        hasReachedMax: hasReachedMax ?? this.hasReachedMax,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props =>
      [status, products, page, hasReachedMax, errorMessage];
}
```

Bloc — `droppable()` is the whole point; appends pages, stops at `hasReachedMax`:

`droppable()` handles the *load-more* fetch; pull-to-refresh is a separate
`restartable()` event that resets to page 1:

```dart
final class ProductsBloc extends Bloc<ProductsEvent, ProductsState> {
  ProductsBloc(this._getProductsUseCase) : super(const ProductsState()) {
    on<ProductsFetched>(_onFetched, transformer: droppable());
    on<ProductsRefreshed>(_onRefreshed, transformer: restartable());
  }

  final GetProductsUseCase _getProductsUseCase;

  Future<void> _onFetched(
    ProductsFetched event,
    Emitter<ProductsState> emit,
  ) async {
    if (state.hasReachedMax) return;
    final result = await _getProductsUseCase(page: state.page + 1);
    switch (result) {
      case Success(:final data):
        emit(state.copyWith(
          status: ProductsStatus.success,
          products: [...state.products, ...data.products],
          page: data.page,
          hasReachedMax: data.hasReachedMax,
        ));
      case FailureResult(:final failure):
        emit(state.copyWith(
          status: ProductsStatus.failure,
          errorMessage: failure.message,
        ));
    }
  }

  Future<void> _onRefreshed(
    ProductsRefreshed event,
    Emitter<ProductsState> emit,
  ) async {
    final result = await _getProductsUseCase(); // page defaults to 1
    switch (result) {
      case Success(:final data):
        emit(ProductsState( // replace the list entirely
          status: ProductsStatus.success,
          products: data.products,
          page: data.page,
          hasReachedMax: data.hasReachedMax,
        ));
      case FailureResult(:final failure):
        emit(state.copyWith(
          status: ProductsStatus.failure,
          errorMessage: failure.message,
        ));
    }
  }
}
```

The page kicks off the first load in `BlocProvider.create`, listens to a
`ScrollController` to request more near the bottom, and wraps the list in a
`RefreshIndicator` for pull-to-refresh. The list shows a trailing spinner while
`!hasReachedMax`:

```dart
// In create:
create: (_) => getIt<ProductsBloc>()..add(const ProductsFetched()),

// Scroll handler — fire only on the RISING EDGE of entering the near-bottom
// zone, not continuously while resting in it.
bool _wasNearBottom = false;
void _onScroll() {
  final nearBottom = _isNearBottom;
  if (nearBottom && !_wasNearBottom) {
    context.read<ProductsBloc>().add(const ProductsFetched());
  }
  _wasNearBottom = nearBottom;
}

// Pull-to-refresh: dispatch then await the next emitted state so the spinner
// stays until the refresh completes.
Future<void> _onRefresh() async {
  final bloc = context.read<ProductsBloc>()..add(const ProductsRefreshed());
  await bloc.stream.first;
}

// Body:
RefreshIndicator(
  onRefresh: _onRefresh,
  child: ListView.builder(
    controller: _scrollController,
    physics: const AlwaysScrollableScrollPhysics(), // allow pull on short lists
    itemCount: state.hasReachedMax
        ? state.products.length
        : state.products.length + 1, // +1 = bottom loader when more remain
    itemBuilder: ...,
  ),
)
```

> **Edge detection matters.** A naive `if (_isNearBottom) add(ProductsFetched())`
> fires on *every* scroll callback while you sit at the bottom. The first page
> loads, you're still near the bottom, so the next page loads immediately too —
> several pages arrive "at once" instead of one per scroll. Guarding on the
> rising edge (`nearBottom && !_wasNearBottom`) fires exactly once per arrival at
> the bottom; once the appended items grow the list, the ratio drops below the
> threshold and re-arms.

`add()` returns `void`, so the `..add(...)` cascade needs no `unawaited`. Register
the bloc as a factory: `getIt.registerFactory(() => ProductsBloc(getIt()))`.

## Example Cubit state (Equatable)

The `isSuccess` flag lets the UI react/navigate.

```dart
final class LoginState extends Equatable {
  const LoginState({
    this.isLoading = false,
    this.isSuccess = false,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isSuccess;
  final String? errorMessage;

  LoginState copyWith({
    bool? isLoading,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return LoginState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [isLoading, isSuccess, errorMessage];
}
```

> `errorMessage` deliberately resets on each `copyWith` (it is not preserved with
> `?? this.errorMessage`) so a stale error does not linger across emits.

## Example Cubit behavior

```dart
final class LoginCubit extends Cubit<LoginState> {
  LoginCubit(this._loginUseCase) : super(const LoginState());

  final LoginUseCase _loginUseCase;

  Future<void> login({
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    final result = await _loginUseCase(
      LoginParams(email: email, password: password),
    );

    switch (result) {
      case Success():
        emit(const LoginState(isSuccess: true));
      case FailureResult(:final failure):
        emit(state.copyWith(isLoading: false, errorMessage: failure.message));
    }
  }
}
```

The UI uses a `BlocListener` to navigate when `isSuccess` becomes true and to
show a localized snackbar when `errorMessage` is non-null. Adjust examples to
project conventions.
