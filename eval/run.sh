#!/usr/bin/env bash
#
# eval/run.sh — prove the generator end-to-end for ALL FIVE stacks in isolated
# throwaway Flutter projects. For each stack:
#   flutter create -> add base+stack packages (latest compatible) -> write the
#   minimal core/ the generated feature imports -> scaffold an `api` feature in
#   that stack -> pub get -> build_runner -> dart format -> flutter analyze
#   (lib/features) -> check_layers.sh. Reports PASS/FAIL per stack.
#
# This compiles + layer-checks the OUTPUT (not string diffs). Bloc must pass
# exactly as today; the other four must match.
#
# Usage: eval/run.sh [workdir]        (default: /tmp/fca_eval)
#        STACKS="bloc riverpod" eval/run.sh   # subset
#
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$SELF_DIR/.." && pwd)/scripts"
WORK="${1:-/tmp/fca_eval}"
STACKS="${STACKS:-bloc riverpod provider getx mobx \
openapi openapi_byid openapi_post openapi_put openapi_delete openapi_altcore \
openapi_values openapi_shapes openapi_oneof \
riverpod_post riverpod_byid riverpod_dioprov provider_post provider_byid \
getx_post getx_byid mobx_post mobx_byid}"
SPEC="$SELF_DIR/fixtures/wizard_world_openapi.json"
CRUD="$SELF_DIR/fixtures/crud_openapi.json"
VAL="$SELF_DIR/fixtures/value_openapi.json"
SHAPES="$SELF_DIR/fixtures/shapes_openapi.json"
ONEOF="$SELF_DIR/fixtures/oneof_openapi.json"

# Scenarios EXPECTED to fail — they encode a known-but-unfixed bug as a standing
# red test without turning the suite red. A scenario flips to XPASS once the
# generator is fixed; that's the signal to promote it out of here into a normal
# required-PASS scenario (which guards against regression).
#
# Currently empty: `openapi_altcore` (feature scaffolded against a renamed core
# layout — core/errors, core/net) was promoted after the generator learned to
# resolve core import paths from the project instead of hardcoding them. Add a
# scenario name here when you want a red test for the next known bug.
XFAIL_STACKS="${XFAIL_STACKS:-}"
is_xfail() { [ -n "$XFAIL_STACKS" ] && case " $XFAIL_STACKS " in *" $1 "*) return 0 ;; esac; return 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
declare -a SUMMARY

write_core() {
  local app="$1" pkg="$2" stack="$3" layout="${4:-std}"

  # Core layout. "std" matches the import paths the generator hardcodes.
  # "alt" is a DIFFERENT but equally valid layout (renamed dirs) used by the
  # openapi_altcore xfail scenario to prove the generator emits portable
  # imports rather than assuming core/error|core/network verbatim. The core
  # itself stays internally consistent — only the generated feature's
  # hardcoded imports should break.
  local errdir netdir
  if [ "$layout" = "alt" ]; then
    errdir="core/errors"; netdir="core/net"
  else
    errdir="core/error"; netdir="core/network"
  fi
  mkdir -p "$app/lib/$errdir" "$app/lib/$netdir" "$app/lib/core/di"

  cat > "$app/lib/$errdir/failures.dart" <<'DART'
sealed class AppFailure implements Exception {
  const AppFailure({required this.message});
  final String message;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure({required super.message});
}

final class ServerFailure extends AppFailure {
  const ServerFailure({required super.message});
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({required super.message});
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure({required super.message});
}
DART

  cat > "$app/lib/$errdir/result.dart" <<DART
import 'package:$pkg/$errdir/failures.dart';

sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.data);
  final T data;
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);
  final AppFailure failure;
}
DART

  cat > "$app/lib/$netdir/error_mapper.dart" <<DART
import 'package:dio/dio.dart';
import 'package:$pkg/$errdir/failures.dart';

AppFailure mapDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.connectionError:
      return const NetworkFailure(message: 'common.network_error');
    case DioExceptionType.badResponse:
      return const ServerFailure(message: 'common.server_error');
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return const UnknownFailure(message: 'common.unknown_error');
  }
}
DART

  # Riverpod has no get_it and its page doesn't import injection.dart.
  if [ "$stack" != "riverpod" ]; then
    cat > "$app/lib/core/di/injection.dart" <<'DART'
import 'package:get_it/get_it.dart';

final GetIt getIt = GetIt.instance;
DART
  fi

  cat > "$app/analysis_options.yaml" <<'YAML'
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  exclude:
    - "**/*.g.dart"

linter:
  rules:
    public_member_api_docs: false
    sort_pub_dependencies: false
    one_member_abstracts: false
YAML
}

run_stack() {
  local stack="$1"
  local pkg="${stack}_app"
  local app="$WORK/$pkg"
  echo "================================================================"
  echo "### STACK: $stack  ($app)"
  echo "================================================================"

  if ! flutter create "$app" >/dev/null 2>&1; then
    SUMMARY+=("$stack: FAIL (flutter create)"); return
  fi
  cd "$app" || { SUMMARY+=("$stack: FAIL (cd)"); return; }

  # Resolve the base state-management stack + whether retrofit is needed.
  local base needs_retrofit=0
  case "$stack" in
    openapi*) base="bloc" ;;
    *_post) base="${stack%_post}" ;;
    *_byid) base="${stack%_byid}" ;;
    *_dioprov) base="${stack%_dioprov}" ;;
    *) base="$stack" ;;
  esac
  case "$stack" in openapi*|*_post|*_byid|*_dioprov) needs_retrofit=1 ;; esac

  local deps="dio json_annotation equatable easy_localization"
  local dev="json_serializable build_runner mocktail very_good_analysis"
  case "$base" in
    bloc)     deps="$deps flutter_bloc bloc get_it" ;;
    riverpod) deps="$deps flutter_riverpod riverpod_annotation"; dev="$dev riverpod_generator" ;;
    provider) deps="$deps provider get_it" ;;
    getx)     deps="$deps get get_it" ;;
    mobx)     deps="$deps mobx flutter_mobx get_it"; dev="$dev mobx_codegen" ;;
  esac
  [ "$needs_retrofit" = 1 ] && { deps="$deps retrofit"; dev="$dev retrofit_generator"; }

  # Add deps + dev in ONE call so the solver co-resolves generator/runtime
  # pairings (e.g. riverpod_annotation with riverpod_generator).
  local allargs="$deps"
  for d in $dev; do allargs="$allargs dev:$d"; done
  echo "--> pub add: $allargs"
  # shellcheck disable=SC2086
  if ! flutter pub add $allargs >/tmp/_eval_add.log 2>&1; then
    echo "  pub add FAILED:"; tail -8 /tmp/_eval_add.log
    SUMMARY+=("$stack: FAIL (pub add)"); return
  fi

  # Alt-core variants render a renamed-but-valid core layout to verify the
  # generator emits portable imports (xfail today — see XFAIL_STACKS).
  local layout=std
  case "$stack" in *altcore) layout=alt ;; esac
  write_core "$app" "$pkg" "$base" "$layout"

  # riverpod_dioprov: seed a project Dio provider so new_feature.sh detects it
  # and wires `ref.watch(dioProvider)` instead of a bare Dio().
  if [ "$stack" = "riverpod_dioprov" ]; then
    mkdir -p "$app/lib/core/network"
    cat > "$app/lib/core/network/dio_provider.dart" <<'DART'
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dioProvider = Provider<Dio>(
  (ref) => Dio(BaseOptions(baseUrl: 'https://example.com')),
);
DART
  fi

  case "$stack" in
    openapi|openapi_altcore)
      scaffold_args=(api items --item item --openapi "$SPEC" --path /Elixirs --stack bloc) ;;
    openapi_values)
      scaffold_args=(api gizmos --item gizmo --openapi "$VAL" --path /gizmos --stack bloc) ;;
    openapi_shapes)
      scaffold_args=(api things --item thing --openapi "$SHAPES" --path /things --stack bloc) ;;
    openapi_oneof)
      scaffold_args=(api pets --item pet --openapi "$ONEOF" --path /pets --stack bloc) ;;
    openapi_byid)
      scaffold_args=(api elixir --item elixir --openapi "$SPEC" --path "/Elixirs/{id}" --stack bloc) ;;
    openapi_post)
      scaffold_args=(api feedback --item feedback --openapi "$SPEC" --path /Feedback --method post --stack bloc) ;;
    openapi_put)
      scaffold_args=(api things --item thing --openapi "$CRUD" --path "/things/{id}" --method put --stack bloc) ;;
    openapi_delete)
      scaffold_args=(api things --item thing --openapi "$CRUD" --path "/things/{id}" --method delete --stack bloc) ;;
    *_post)
      scaffold_args=(api feedback --item feedback --openapi "$SPEC" --path /Feedback --method post --stack "$base") ;;
    *_byid)
      scaffold_args=(api elixir --item elixir --openapi "$SPEC" --path "/Elixirs/{id}" --stack "$base") ;;
    riverpod_dioprov)
      scaffold_args=(api items --item item --openapi "$SPEC" --path /Elixirs --stack riverpod) ;;
    *)
      scaffold_args=(api items --item item --stack "$stack") ;;
  esac
  echo "--> scaffold: new_feature.sh ${scaffold_args[*]}"
  if ! "$SCRIPTS/new_feature.sh" "${scaffold_args[@]}" >/dev/null 2>&1; then
    SUMMARY+=("$stack: FAIL (scaffold)"); return
  fi

  echo "--> build_runner"
  if ! dart run build_runner build --delete-conflicting-outputs >/tmp/_eval_br.log 2>&1; then
    echo "  build_runner FAILED:"; tail -12 /tmp/_eval_br.log
    if is_xfail "$stack"; then
      SUMMARY+=("$stack: XFAIL (build_runner) — expected; reproduces the hardcoded-core-import bug")
    else
      SUMMARY+=("$stack: FAIL (build_runner)")
    fi
    return
  fi

  dart format lib >/dev/null 2>&1

  echo "--> flutter analyze lib/features"
  if flutter analyze lib/features >/tmp/_eval_an.log 2>&1; then
    local ana="OK"
  else
    local ana="FAIL"
    echo "  analyze issues:"; grep -E "•|error|warning|info" /tmp/_eval_an.log | head -15
  fi

  echo "--> check_layers.sh"
  if "$SCRIPTS/check_layers.sh" lib >/dev/null 2>&1; then
    local cl="OK"
  else
    local cl="FAIL"; "$SCRIPTS/check_layers.sh" lib | head -8
  fi

  # Value gate (analyze proves it COMPILES; this proves it BEHAVES). The
  # openapi_values scenario scaffolds a feature from value_openapi.json, then a
  # known JSON payload is pushed through the generated Model.fromJson ->
  # toEntity() and the resulting entity values are asserted with `flutter test`.
  # Catches type-correct-but-wrong codegen (a mapper that drops/swaps fields).
  local vt="SKIP" vt_paths=""
  case "$stack" in
    openapi_values)
      mkdir -p "$app/test"
      # (a) value gate: model -> entity carries values.
      cat > "$app/test/gizmo_mapping_test.dart" <<DART
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/gizmos/data/models/gizmo_model.dart';

void main() {
  test('GizmoModel.fromJson -> toEntity carries every field value', () {
    final model = GizmoModel.fromJson(<String, dynamic>{
      'id': 7,
      'name': 'Sprocket',
      'price': 9.5,
      'active': true,
    });
    final entity = model.toEntity();
    expect(entity.id, 7);
    expect(entity.name, 'Sprocket');
    expect(entity.price, 9.5);
    expect(entity.active, true);
  });
}
DART
      # (b) runtime gate (#2): the whole generated chain RUNS, not just compiles.
      # A fake datasource feeds real RepositoryImpl -> UseCase -> Cubit; assert
      # the cubit reaches success with correctly mapped entities. Proves the
      # data/domain/presentation-state wiring executes end-to-end.
      cat > "$app/test/gizmo_runtime_test.dart" <<DART
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:$pkg/features/gizmos/data/datasources/gizmos_remote_data_source.dart';
import 'package:$pkg/features/gizmos/data/models/gizmo_model.dart';
import 'package:$pkg/features/gizmos/data/repositories/gizmos_repository_impl.dart';
import 'package:$pkg/features/gizmos/domain/usecases/get_gizmos_use_case.dart';
import 'package:$pkg/features/gizmos/presentation/cubit/gizmos_cubit.dart';

class _FakeGizmosRemoteDataSource implements GizmosRemoteDataSource {
  @override
  Future<List<GizmoModel>> fetchAll() async => const <GizmoModel>[
        GizmoModel(id: 1, name: 'A', price: 1.0, active: true),
        GizmoModel(id: 2, name: 'B', price: 2.0, active: false),
      ];
}

// Compile-time guard: the use case must be a plain (non-final) class so a test
// double can implement it. If the generator regresses to a final use case class
// this file will not compile and the value gate fails.
class _MockGetGizmosUseCase extends Mock implements GetGizmosUseCase {}

void main() {
  test('feature runs: datasource -> repository -> usecase -> cubit success', () async {
    final cubit = GizmosCubit(
      GetGizmosUseCase(GizmosRepositoryImpl(_FakeGizmosRemoteDataSource())),
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, GizmosStatus.success);
    expect(cubit.state.items.length, 2);
    expect(cubit.state.items.first.id, 1);
    expect(cubit.state.items.first.name, 'A');
  });

  test('use case is mockable (plain class, not final) for unit testing', () {
    expect(_MockGetGizmosUseCase(), isA<GetGizmosUseCase>());
  });
}
DART
      # (c) render gate (#2 fully): pump the ACTUAL generated page — exercising
      # getIt DI registration, the widget tree, BlocProvider/Builder, and
      # easy_localization .tr() — and assert the success list renders.
      cat > "$app/test/gizmo_render_test.dart" <<DART
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:$pkg/core/di/injection.dart';
import 'package:$pkg/features/gizmos/data/datasources/gizmos_remote_data_source.dart';
import 'package:$pkg/features/gizmos/data/models/gizmo_model.dart';
import 'package:$pkg/features/gizmos/data/repositories/gizmos_repository_impl.dart';
import 'package:$pkg/features/gizmos/domain/usecases/get_gizmos_use_case.dart';
import 'package:$pkg/features/gizmos/presentation/cubit/gizmos_cubit.dart';
import 'package:$pkg/features/gizmos/presentation/pages/gizmos_page.dart';

class _FakeGizmosRemoteDataSource implements GizmosRemoteDataSource {
  @override
  Future<List<GizmoModel>> fetchAll() async => const <GizmoModel>[
        GizmoModel(id: 1, name: 'A', price: 1, active: true),
        GizmoModel(id: 2, name: 'B', price: 2, active: false),
      ];
}

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      <String, dynamic>{};
}

void main() {
  testWidgets('GizmosPage renders the success list via getIt DI + l10n',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();

    getIt.registerFactory<GizmosCubit>(
      () => GizmosCubit(GetGizmosUseCase(GizmosRepositoryImpl(
        _FakeGizmosRemoteDataSource(),
      ))),
    );
    addTearDown(getIt.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en')],
        path: 'lang',
        assetLoader: const _EmptyAssetLoader(),
        saveLocale: false,
        child: const MaterialApp(home: GizmosPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GizmosView), findsOneWidget);
    expect(find.text('gizmos.title'), findsOneWidget); // .tr() returned the key
    expect(find.byType(ListTile), findsNWidgets(2)); // success list rendered
  });
}
DART
      vt_paths="test/gizmo_mapping_test.dart test/gizmo_runtime_test.dart test/gizmo_render_test.dart"
      ;;
    openapi_shapes)
      mkdir -p "$app/test"
      cat > "$app/test/thing_mapping_test.dart" <<DART
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/things/data/models/thing_model.dart';

void main() {
  test('ThingModel.fromJson -> toEntity handles allOf merge, maps, nullable', () {
    final model = ThingModel.fromJson(<String, dynamic>{
      'id': 3,
      'name': 'Bolt',
      'extra': 'hex',
      'tags': <String, dynamic>{'a': '1', 'b': '2'},
      'note': null,
    });
    final entity = model.toEntity();
    expect(entity.id, 3); // allOf base
    expect(entity.name, 'Bolt'); // allOf base
    expect(entity.extra, 'hex'); // allOf extension
    expect(entity.tags['a'], '1'); // additionalProperties map
    expect(entity.tags.length, 2);
    expect(entity.note, isNull); // nullable preserved
  });
}
DART
      vt_paths="test/thing_mapping_test.dart"
      ;;
    openapi_oneof)
      vt_paths="test/pet_mapping_test.dart"; mkdir -p "$app/test"
      cat > "$app/test/pet_mapping_test.dart" <<DART
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/pets/data/models/pet_model.dart';
import 'package:$pkg/features/pets/domain/entities/pet.dart';

void main() {
  test('PetModel.fromJson dispatches oneOf by discriminator to typed entities', () {
    final Pet cat = PetModel.fromJson(<String, dynamic>{
      'id': 1,
      'petType': 'cat',
      'name': 'Tom',
      'lives': 9,
    }).toEntity();
    expect(cat, isA<Cat>());
    expect(cat.id, 1); // lifted base getter, read polymorphically
    expect(cat.name, 'Tom');
    expect((cat as Cat).lives, 9);

    final Pet dog = PetModel.fromJson(<String, dynamic>{
      'id': 2,
      'petType': 'dog',
      'name': 'Rex',
      'goodBoy': true,
    }).toEntity();
    expect(dog, isA<Dog>());
    expect(dog.id, 2); // base getter
    expect((dog as Dog).goodBoy, true);
  });
}
DART
      ;;
  esac
  if [ -n "$vt_paths" ]; then
    echo "--> flutter test (value + runtime gates)"
    # shellcheck disable=SC2086
    if flutter test $vt_paths -r compact >/tmp/_eval_vt.log 2>&1; then
      vt="OK"
    else
      vt="FAIL"; echo "  value/runtime test issues:"; tail -25 /tmp/_eval_vt.log
    fi
  fi

  # dioProvider gate: when a project Dio provider exists, the generated Riverpod
  # datasource provider must wire `ref.watch(dioProvider)`, not a bare Dio().
  local dp="SKIP"
  if [ "$stack" = "riverpod_dioprov" ]; then
    if grep -rqsF 'ref.watch(dioProvider)' "$app"/lib/features/*/presentation/notifier/*.dart \
       && ! grep -rqsE 'RemoteDataSourceImpl\(Dio\(\)\)' "$app"/lib/features/*/presentation/notifier/*.dart; then
      dp="OK"
    else
      dp="FAIL"; echo "  dioProvider not wired into notifier:"
      grep -rnsE 'RemoteDataSourceImpl\(' "$app"/lib/features/*/presentation/notifier/*.dart | head
    fi
  fi

  local passed=0
  [ "$ana" = "OK" ] && [ "$cl" = "OK" ] && passed=1
  [ "$vt" = "FAIL" ] && passed=0
  [ "$dp" = "FAIL" ] && passed=0

  local vsuffix=""
  [ "$vt" != "SKIP" ] && vsuffix=" values=$vt"
  [ "$dp" != "SKIP" ] && vsuffix="$vsuffix dio=$dp"

  if is_xfail "$stack"; then
    if [ "$passed" -eq 1 ]; then
      SUMMARY+=("$stack: XPASS (analyze=$ana check_layers=$cl$vsuffix) — generator looks fixed; promote it out of XFAIL_STACKS")
    else
      SUMMARY+=("$stack: XFAIL (analyze=$ana check_layers=$cl$vsuffix) — expected; reproduces the hardcoded-core-import bug")
    fi
  elif [ "$passed" -eq 1 ]; then
    SUMMARY+=("$stack: PASS (analyze=$ana check_layers=$cl$vsuffix)")
  else
    SUMMARY+=("$stack: FAIL (analyze=$ana check_layers=$cl$vsuffix)")
  fi
}

# --- Negative paths: the generator must FAIL gracefully on bad input ---------
# Positive scenarios prove good input produces good output; these prove bad input
# is rejected with a non-zero exit (and, where applicable, a clear message) —
# instead of silently emitting broken Dart. They need only a valid pubspec, so
# one bare `flutter create` covers all cases (no pub add / build_runner).
#
# assert_fail <label> <expected-stderr-substr|""> <cmd...>
assert_fail() {
  local label="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  ✗ negative[$label]: expected non-zero exit, got 0"; return 1
  fi
  if [ -n "$want" ] && ! printf '%s' "$out" | grep -qiF "$want"; then
    echo "  ✗ negative[$label]: exit $rc but message missing '$want'"
    echo "    last line: $(printf '%s' "$out" | tail -1)"; return 1
  fi
  echo "  ✓ negative[$label]: rejected (exit $rc)"; return 0
}

run_negatives() {
  echo "================================================================"
  echo "### NEGATIVE PATHS (generator error handling)"
  echo "================================================================"
  local app="$WORK/neg_app"
  if ! flutter create "$app" >/dev/null 2>&1; then
    SUMMARY+=("negatives: FAIL (flutter create)"); return
  fi
  cd "$app" || { SUMMARY+=("negatives: FAIL (cd)"); return; }

  local ok=1
  # 1. --openapi spec file that doesn't exist (validated before any scaffolding).
  assert_fail "missing-spec" "spec file not found" \
    "$SCRIPTS/new_feature.sh" api foo --openapi /no/such/spec.json --path /x --stack bloc || ok=0
  # 2. --path that isn't in the spec (python rejects after model build starts).
  assert_fail "endpoint-not-in-spec" "not in spec" \
    "$SCRIPTS/new_feature.sh" api bar --openapi "$SPEC" --path /NopeNotHere --stack bloc || ok=0
  # 3. --json pointed at malformed JSON (must fail, not emit garbage).
  printf '{ this is not valid json' > "$WORK/_bad.json"
  assert_fail "malformed-json" "generation failed" \
    "$SCRIPTS/new_feature.sh" api baz --json "$WORK/_bad.json" --stack bloc || ok=0
  # 4. Positive control — a non-snake_case feature name is rejected by arg parsing.
  assert_fail "bad-name" "snake_case" \
    "$SCRIPTS/new_feature.sh" api BadName --stack bloc || ok=0
  # 5. Positive control — an unknown --stack is rejected.
  assert_fail "bad-stack" "stack must be one of" \
    "$SCRIPTS/new_feature.sh" api qux --stack nope || ok=0

  if [ "$ok" = 1 ]; then
    SUMMARY+=("negatives: PASS (5 error paths rejected)")
  else
    SUMMARY+=("negatives: FAIL (an error path was not handled)")
  fi
}

for s in $STACKS; do run_stack "$s"; done

# Negative paths run by default; set RUN_NEGATIVES=0 to skip (e.g. quick subset).
[ "${RUN_NEGATIVES:-1}" = 1 ] && run_negatives

echo
echo "================ EVAL SUMMARY ================"
fail=0
xpass=0
for line in "${SUMMARY[@]}"; do
  echo "  $line"
  case "$line" in
    *XFAIL*) : ;;        # expected failure — does NOT fail the suite
    *XPASS*) xpass=1 ;;  # known bug now passes — surface loudly, don't fail CI
    *FAIL*)  fail=1 ;;
  esac
done
echo "============================================="
[ "$xpass" -eq 1 ] && echo "NOTE: an XFAIL scenario now PASSES — the generator may be fixed; promote it out of XFAIL_STACKS."
[ "$fail" -eq 0 ] && echo "ALL STACKS PASS (xfail tolerated)" || echo "SOME STACKS FAILED"
exit "$fail"
