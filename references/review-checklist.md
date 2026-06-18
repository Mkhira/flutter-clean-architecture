# Review Checklist

When reviewing Flutter/Dart code, check the following. Report findings like a
senior reviewer: lead with severity, point at the exact file/line, and say what
to do. Don't pad a review with low-value nits to look thorough — a short list of
real issues beats a long list of noise.

## Severity tiers

Tag every finding with one of:

- **🔴 blocker** — fix before merge. Breaks an architectural guarantee, ships a
  real defect, leaks errors/secrets, or won't build/run correctly.
- **🟡 should-fix** — fix unless there's a deliberate, stated reason. Degrades
  maintainability or correctness-under-edge-cases but doesn't break a guarantee.
- **🔵 nit** — optional polish. Mention briefly; never block on it.

"Too large / bloated / unnecessary" is subjective, so each such check below
carries a concrete trigger. Treat the numbers as defaults, not laws — a
cohesive 220-line widget can be fine; an incoherent 120-line one may not be.

## Architecture

- 🔴 Does any `domain/` file import Flutter/Dio/Retrofit/GetIt/json_annotation/
  state-management infra? Run `scripts/check_layers.sh` — it's a hard gate, not
  a judgment call.
- 🔴 Does presentation reach into `data/` directly, skipping the domain
  contract? Presentation depends on domain (and its own UI/state) only.
- 🔴 Does any infrastructure error (`DioException`, raw `Response`, a
  persistence exception) reach a Cubit/widget? It must be mapped to `AppFailure`
  at the data boundary.
- 🔴 Were generated files (`*.g.dart`, `*.freezed.dart`) hand-edited?
- 🟡 Is business logic sitting inside a widget? (🔴 if it's non-trivial domain
  logic that belongs in a use case/repository.)
- 🟡 Are there layers that don't earn their keep — a `domain/`+`data/` pair for a
  static/UI-only feature, a use case that only forwards a call with no added
  behavior, an abstract repository with one impl and no test/swap need, or empty
  folders? Over-abstraction is a finding, not a virtue.
- 🟡 Are feature folders coherent (each file in the layer it belongs to, no
  cross-feature reach-through)?

## SOLID

- 🟡 Is a widget doing too much? Trigger: a `build()` over ~150 lines, a widget
  class over ~250, or one widget mixing > 3 concerns (layout + data fetch +
  formatting + navigation). Fix: extract sub-widgets; move logic to the state
  holder.
- 🟡 Does a class hold more than one responsibility (SRP)? Trigger: it changes
  for two unrelated reasons.
- 🟡 Is a repository interface bloated (ISP)? Trigger: > ~7 methods, or methods
  spanning unrelated capabilities. Fix: split by capability.
- 🟡 Are dependencies constructed deep inside a class instead of injected (DIP)?
  (🔴 if it makes a critical path untestable.)
- 🟡 Are abstractions useful rather than ceremonial — does each interface have a
  real second implementation, a test seam, or a genuine boundary behind it?

## State layer (per the project's stack)

Applies to whichever stack the project uses (run `scripts/detect_stack.sh`).
Stack-agnostic checks:

- 🔴 Is the state holder in `presentation/` only, never in `domain`/`data`?
- 🔴 Does it call a use case (or repository) and translate the shared `Result`
  into UI state — never touching `DioException`?
- 🟡 Is the error surfaced as a localization key (`AppFailure.message`), resolved
  with `.tr()` at the widget?
- 🟡 Is the state immutable / observable-correct, with a single consistent style?
  (🔴 if the mistake causes missed rebuilds or stale UI.)
- 🟡 Are duplicate submits / overlapping loads handled (a guard or transformer)?

Per-stack specifics (🟡 unless the slip breaks correctness, then 🔴):

- **Bloc/Cubit:** side effects in `BlocListener`; `bloc_concurrency`
  (`droppable`/`restartable`/`sequential`) where event handling needs it.
- **Riverpod:** DI is providers (no `get_it`); failures thrown so `AsyncError`
  carries them; UI uses `.when`; `ref.watch`/`read`/`listen` used correctly.
- **Provider:** `notifyListeners()` after every mutation; DI still GetIt.
- **GetX:** state only (`Obx` + `.obs`); **no** `Get.put`/`GetMaterialApp` — GetIt
  for DI, go_router for routing.
- **MobX:** mutations only inside `@action`; reactive UI in `Observer`; store
  registered in GetIt.

## Networking

- 🔴 Are request/response models based on real JSON/spec, not invented? (This is
  a non-negotiable skill rule.)
- 🔴 Do the model field names/types/nullability match the contract?
- 🔴 Are `DioException` / raw-response errors mapped to `AppFailure` before
  leaving `data/`?
- 🔴 Are tokens / PII kept out of logs?
- 🟡 Are Retrofit clients and models generated (not stale) and correct?

## Theme

- 🟡 Are colors/text styles consumed from the theme, not hardcoded, where a token
  exists?
- 🟡 Is RTL respected (directional padding/alignment — `EdgeInsetsDirectional`,
  `AlignmentDirectional`)?
- 🔵 Are brand tokens exposed via `ThemeExtension` rather than scattered
  constants?

## Localization

- 🔴 Is every key present in BOTH `assets/lang/en.json` and `assets/lang/ar.json`
  (a missing key fails at runtime)?
- 🔴 Is `assets/lang/` declared in `pubspec.yaml`?
- 🔴 Are locale codes valid (no invented region codes)?
- 🟡 Are user-facing strings localized (no literal copy in widgets)?
- 🟡 Is `flutter_localizations` present and are iOS `CFBundleLocalizations` set?
- 🟡 Is Arabic/RTL respected?

## Codegen

- 🔴 Were generated inputs changed (Retrofit/JsonSerializable/Freezed/Envied)
  without re-running build_runner? Stale/missing `.g.dart` breaks the build.
- 🔴 Was any generated file edited by hand?

## Testing

- 🟡 Are new behaviors tested?
- 🟡 Are the state-layer flows tested (per the stack's tool: bloc_test, or a plain
  unit test on the notifier/controller/store, or `ProviderContainer` overrides)?
- 🟡 Are mappers/error cases tested?
- 🟡 Are mocks/fallback values configured? (🔴 if their absence stops tests
  compiling.)
- 🔵 Are widget states tested when useful?

## Validation (all required — these are gates, not findings)

- `dart format .`
- `flutter analyze`
- `scripts/check_layers.sh` after any domain edit
- relevant `flutter test`
- conditional build_runner only when generated inputs changed
