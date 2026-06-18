#!/usr/bin/env bash
#
# new_feature.sh — scaffold a feature's mechanical skeleton on disk so the agent
# spends tokens only on real logic (mappers, use-case bodies, handlers), not on
# emitting boilerplate folder trees and empty class shells.
#
# Usage (run from the Flutter project root):
#   scripts/new_feature.sh <type> <feature_name> [lib_root] [--item <singular>]
#
#   <type>           ui | api | form
#   <feature_name>   snake_case (e.g. order_history)
#   [lib_root]       defaults to "lib"
#   --item <name>    snake_case singular for the entity/model (api only). Lets a
#                    collection-named feature ('elixirs') produce a singular item
#                    'Elixir' while collection types stay plural. Defaults to the
#                    feature name.
#
# Types (respecting the skill's layering — no empty layers):
#   ui    presentation-only page (no domain/data — nothing to abstract)
#   api   full clean arch: domain (entity/repo/usecase) + data (model/datasource/
#         repo impl) + presentation (Cubit + page)
#   form  presentation Cubit + page with a validated Form (wire a use case later)
#
# After scaffolding it prints the exact DI / build_runner / l10n follow-ups.
# It NEVER overwrites an existing feature directory.
#
set -euo pipefail

# --- args ------------------------------------------------------------------
USAGE="usage: scripts/new_feature.sh <ui|api|form> <feature_name> [lib_root] [--item <singular>] [--json <file> | --openapi <spec> --path <path> [--method get]] [--stack <bloc|riverpod|provider|getx|mobx>]"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM=""
JSON=""
STACK=""
OPENAPI=""
APIPATH=""
METHOD="get"
POSITIONAL=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --item) ITEM="${2:-}"; shift 2 ;;
    --item=*) ITEM="${1#*=}"; shift ;;
    --json) JSON="${2:-}"; shift 2 ;;
    --json=*) JSON="${1#*=}"; shift ;;
    --stack) STACK="${2:-}"; shift 2 ;;
    --stack=*) STACK="${1#*=}"; shift ;;
    --openapi) OPENAPI="${2:-}"; shift 2 ;;
    --openapi=*) OPENAPI="${1#*=}"; shift ;;
    --path) APIPATH="${2:-}"; shift 2 ;;
    --path=*) APIPATH="${1#*=}"; shift ;;
    --method) METHOD="${2:-}"; shift 2 ;;
    --method=*) METHOD="${1#*=}"; shift ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    -*) echo "error: unknown option '$1'" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
if [ "${#POSITIONAL[@]}" -gt 0 ]; then
  set -- "${POSITIONAL[@]}"
else
  set --
fi

TYPE="${1:-}"
NAME="${2:-}"
ROOT="${3:-lib}"
ROOT="${ROOT%/}"          # normalize a trailing slash so prefix-strips are exact
[ -z "$ROOT" ] && ROOT="." # `lib/` -> `lib`; `/` -> `.`

if [ -z "$TYPE" ] || [ -z "$NAME" ]; then
  echo "$USAGE" >&2
  exit 2
fi

case "$TYPE" in
  ui|api|form) ;;
  *) echo "error: <type> must be one of: ui | api | form" >&2; exit 2 ;;
esac

if ! printf '%s' "$NAME" | grep -qE '^[a-z][a-z0-9_]*$'; then
  echo "error: <feature_name> must be snake_case (^[a-z][a-z0-9_]*\$): '$NAME'" >&2
  exit 2
fi

# Item (singular) name for the entity/model; defaults to the feature name.
if [ -z "$ITEM" ]; then
  ITEM="$NAME"
fi
if ! printf '%s' "$ITEM" | grep -qE '^[a-z][a-z0-9_]*$'; then
  echo "error: --item must be snake_case (^[a-z][a-z0-9_]*\$): '$ITEM'" >&2
  exit 2
fi
if [ "$ITEM" != "$NAME" ] && [ "$TYPE" != "api" ]; then
  echo "note: --item only affects the 'api' type; ignoring for '$TYPE'." >&2
fi

# --json: infer the entity + model (incl. nested) from a sample response.
if [ -n "$JSON" ]; then
  if [ "$TYPE" != "api" ]; then
    echo "error: --json only applies to the 'api' type." >&2
    exit 2
  fi
  if [ ! -f "$JSON" ]; then
    echo "error: --json file not found: '$JSON'" >&2
    exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: --json needs python3 on PATH." >&2
    exit 2
  fi
fi

# --openapi: generate accurate models + a Retrofit client from a spec contract.
if [ -n "$OPENAPI" ]; then
  if [ "$TYPE" != "api" ]; then
    echo "error: --openapi only applies to the 'api' type." >&2; exit 2
  fi
  if [ -n "$JSON" ]; then
    echo "error: pass either --json or --openapi, not both." >&2; exit 2
  fi
  if [ ! -f "$OPENAPI" ]; then
    echo "error: --openapi spec file not found: '$OPENAPI'" >&2; exit 2
  fi
  if [ -z "$APIPATH" ]; then
    echo "error: --openapi requires --path <endpoint> (e.g. --path /Elixirs)." >&2
    exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: --openapi needs python3 on PATH." >&2; exit 2
  fi
fi

METHOD="$(printf '%s' "$METHOD" | tr '[:upper:]' '[:lower:]')"
case "$METHOD" in
  get|post|put|patch|delete) ;;
  *) echo "error: --method must be get|post|put|patch|delete (got '$METHOD')." >&2; exit 2 ;;
esac
if [ "$METHOD" != "get" ] && [ -z "$OPENAPI" ]; then
  echo "error: --method $METHOD requires --openapi (the contract supplies the" \
       "verb, path params and request body)." >&2
  exit 2
fi

# State-management stack for the presentation layer (domain/data are identical).
if [ -z "$STACK" ]; then
  STACK="bloc"
fi
# Command-style generation = any non-GET verb, OR a GET with a path param
# (fetch-by-id). The engine generates these end-to-end (data/domain + the active
# stack's command/detail presentation); the collection GET keeps the per-stack
# list presentation.
IS_COMMAND=0
if [ "$METHOD" != "get" ]; then
  IS_COMMAND=1
elif [ -n "$OPENAPI" ] && printf '%s' "$APIPATH" | grep -q '{'; then
  IS_COMMAND=1
fi
case "$STACK" in
  bloc|riverpod|provider|getx|mobx) ;;
  *) echo "error: --stack must be one of: bloc | riverpod | provider | getx | mobx" >&2; exit 2 ;;
esac
if [ "$STACK" != "bloc" ] && [ "$TYPE" != "api" ]; then
  echo "note: --stack currently branches only the 'api' presentation; '$TYPE' uses its default." >&2
fi

if [ ! -f pubspec.yaml ]; then
  echo "error: run from the Flutter project root (no pubspec.yaml here)." >&2
  exit 1
fi

PKG="$(grep -E '^name:' pubspec.yaml | head -1 | awk '{print $2}')"
if [ -z "$PKG" ]; then
  echo "error: could not read package name from pubspec.yaml." >&2
  exit 1
fi

# --- SDK compatibility: the generated code uses Dart 3 language features -----
# (sealed classes, switch-expression patterns, final class). Adapt to the
# CURRENT environment: detect the project's declared min Dart (pubspec
# `environment: sdk:`) and the installed Dart, and warn if either is below the
# Dart 3 floor — the scaffold would not compile there. We detect and guide; we
# don't edit pubspec or maintain a separate pre-3 codegen path.
REQ_DART="3.0.0"
_ver_num() { printf '%s' "$1" | awk -F. '{printf "%d", ($1*10000)+($2*100)+($3+0)}'; }
# Lower bound of `environment: sdk:` (matches '>=X.Y.Z' / '^X.Y.Z'; ignores the
# `sdk: flutter` path dependency, which has no digit).
_min_dart() {
  grep -E "^[[:space:]]+sdk:[[:space:]]*['\"]?[\^>= ]*[0-9]" pubspec.yaml 2>/dev/null \
    | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}
PROJ_DART="$(_min_dart || true)"   # || true: no `environment: sdk:` line must not abort under `set -e`
INST_DART="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [ -n "$PROJ_DART" ] && [ "$(_ver_num "$PROJ_DART")" -lt "$(_ver_num "$REQ_DART")" ]; then
  {
    echo "new_feature: pubspec 'environment: sdk:' min is $PROJ_DART, but generated"
    echo "  features use Dart $REQ_DART features (sealed classes, patterns). Bump the"
    echo "  constraint to  sdk: '^$REQ_DART'  (or newer) or the scaffold won't compile."
  } >&2
fi
if [ -n "$INST_DART" ] && [ "$(_ver_num "$INST_DART")" -lt "$(_ver_num "$REQ_DART")" ]; then
  {
    echo "new_feature: installed Dart is $INST_DART (< $REQ_DART). The generated code"
    echo "  uses Dart 3 features and will not compile on this SDK."
  } >&2
fi

# --- resolve shared core import paths from the ACTUAL project layout --------
# Generated code imports the shared Result / AppFailure / Dio-error-mapper / DI
# locator from core/. Projects don't all lay these out as core/error|network|di
# verbatim, so locate each by the symbol it defines (anywhere under lib/ outside
# features/) and emit imports against THAT path. When a file doesn't exist yet
# (fresh project), fall back to the documented convention — the registration
# hints printed at the end then tell the user where to create it.
# Assumption: Result/Success/FailureResult live together (the skill's scaffold);
# a project that splits them across files should adjust the generated import.
# Does the project already have a core/ layer? (If so, a missing symbol means
# the project names it differently — worth a heads-up, not silent fallback.)
_has_core() { find "$ROOT" -type d -name core 2>/dev/null | grep -q .; }

_resolve_core() {
  # $1 = human label; $2 = ERE identifying the defining file;
  # $3 = fallback lib-relative path
  local label="$1" pattern="$2" fallback="$3" matches count hit
  matches="$(grep -rlE "$pattern" "$ROOT" --include='*.dart' 2>/dev/null \
            | grep -v '/features/' | LC_ALL=C sort || true)"
  count="$(printf '%s' "$matches" | grep -c . || true)"
  if [ "${count:-0}" -eq 0 ]; then
    # Not found. Silent for a fresh project (no core yet); warn for an existing
    # one — its error/DI primitive is probably named differently (e.g. fpdart
    # `Either`, a Freezed failure union, `GetIt.I`), so the convention import we
    # emit may be wrong and need a one-line edit.
    if _has_core; then
      {
        echo "new_feature: couldn't find the $label symbol under $ROOT/ —"
        echo "  assuming '$fallback'. If your project names it differently,"
        echo "  fix the generated import (or rename to the convention)."
      } >&2
    fi
    printf '%s' "$fallback"
    return
  fi
  hit="$(printf '%s\n' "$matches" | head -1)"
  if [ "${count:-0}" -gt 1 ]; then
    # Like detect_stack.sh, don't pick silently — name the choice and the rest
    # on stderr so a wrong guess is visible, not buried in a broken import.
    {
      echo "new_feature: $label matches $count files; importing the first:"
      printf '%s\n' "$matches" | sed -e "s#^#    #" \
        -e "1s/\$/   <- chosen/"
      echo "  if that's wrong, move/rename so one file owns the symbol."
    } >&2
  fi
  printf '%s' "${hit#"$ROOT"/}"
}
# Patterns are broadened past the skill's exact scaffold to tolerate common
# naming: Result as a class OR typedef; AppFailure or a bare Failure base;
# alternative mapper names; GetIt.instance, GetIt.I, or `= GetIt(`.
IMP_RESULT="$(_resolve_core 'Result' '(class|typedef)[[:space:]]+Result[[:space:]<=]' 'core/error/result.dart')"
IMP_FAILURES="$(_resolve_core 'AppFailure' 'class[[:space:]]+(App)?Failure[ {<]' 'core/error/failures.dart')"
IMP_ERRMAP="$(_resolve_core 'Dio error mapper' 'mapDioException|mapDioError|toAppFailure' 'core/network/error_mapper.dart')"
IMP_DI="$(_resolve_core 'GetIt locator' 'GetIt\.instance|GetIt\.I[^a-zA-Z]|=[[:space:]]*GetIt\(' 'core/di/injection.dart')"
# Bridge the resolved paths to the python generators (they write Dart directly).
export FCA_IMP_RESULT="$IMP_RESULT" FCA_IMP_FAILURES="$IMP_FAILURES"
export FCA_IMP_ERRMAP="$IMP_ERRMAP" FCA_IMP_DI="$IMP_DI"

# --- resolve the project's Riverpod Dio provider (riverpod + --openapi only) --
# The Retrofit-backed datasource needs a configured Dio. Rather than emit a bare
# baseUrl-less `Dio()`, find the project's Dio provider (`Provider<Dio>` or an
# `@riverpod Dio dio(Ref …)`) and reference it via `ref.watch(<name>)`. Prints
# "providerName|libRelPath"; empty when none exists (then the generator falls
# back to `Dio()` and we warn for an established project).
_resolve_dio_provider() {
  [ "$STACK" = "riverpod" ] || return 0
  local f name fn
  # Form A: an explicit `name = …Provider<Dio>` declaration.
  f="$(grep -rlE 'Provider<Dio>' "$ROOT" --include='*.dart' 2>/dev/null \
       | grep -v '/features/' | grep -v '\.g\.dart' | LC_ALL=C sort | head -1 || true)"
  if [ -n "$f" ]; then
    name="$(grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[A-Za-z0-9_.]*Provider<Dio>' "$f" \
            | head -1 | sed -E 's/[[:space:]]*=.*//' || true)"
  fi
  # Form B: riverpod codegen source `@riverpod Dio dio(Ref …)` -> `dioProvider`.
  if [ -z "${name:-}" ]; then
    f="$(grep -rlE '^[[:space:]]*Dio[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*Ref' "$ROOT" --include='*.dart' 2>/dev/null \
         | grep -v '/features/' | grep -v '\.g\.dart' | LC_ALL=C sort | head -1 || true)"
    if [ -n "$f" ] && grep -q '@riverpod' "$f"; then
      fn="$(grep -oE 'Dio[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*Ref' "$f" \
            | head -1 | sed -E 's/Dio[[:space:]]+//; s/[[:space:]]*\(.*//' || true)"
      [ -n "$fn" ] && name="${fn}Provider"
    fi
  fi
  if [ -n "${name:-}" ] && [ -n "${f:-}" ]; then
    printf '%s|%s' "$name" "${f#"$ROOT"/}"
  fi
  return 0   # never non-zero: a failing $() under `set -e` would abort the script
}
export FCA_DIO_PROVIDER="" FCA_DIO_PROVIDER_IMPORT=""
if [ "$STACK" = "riverpod" ]; then
  DIO_PROV="$(_resolve_dio_provider || true)"
  if [ -n "$DIO_PROV" ]; then
    export FCA_DIO_PROVIDER="${DIO_PROV%%|*}" FCA_DIO_PROVIDER_IMPORT="${DIO_PROV#*|}"
  elif [ -n "$OPENAPI" ] && _has_core; then
    {
      echo "new_feature: no Dio provider (Provider<Dio> / @riverpod Dio) found —"
      echo "  the generated datasource provider will use a bare Dio() with no"
      echo "  baseUrl. Wire it to your configured Dio provider."
    } >&2
  fi
fi

FEATURE_DIR="$ROOT/features/$NAME"
if [ -e "$FEATURE_DIR" ]; then
  echo "error: '$FEATURE_DIR' already exists — refusing to overwrite." >&2
  exit 1
fi

# --- name helpers ----------------------------------------------------------
snake_to_pascal() {
  printf '%s' "$1" | awk -F'_' '{s="";for(i=1;i<=NF;i++)s=s toupper(substr($i,1,1)) substr($i,2);print s}'
}

# Feature (collection) names.
PASCAL="$(snake_to_pascal "$NAME")"
CAMEL="$(printf '%s%s' "$(printf '%s' "$PASCAL" | cut -c1 | tr '[:upper:]' '[:lower:]')" "$(printf '%s' "$PASCAL" | cut -c2-)")"
# Item (singular) names — used for the entity + model only.
IPASCAL="$(snake_to_pascal "$ITEM")"

# Reads a template from stdin, substitutes placeholders, writes to $1.
# Placeholders (in BOTH the destination path and content):
#   __PKG__   package name
#   __NAME__  feature snake_case      __PASCAL__  feature Pascal   __CAMEL__ feature camel
#   __ITEM__  item snake_case         __IPASCAL__ item Pascal
# Dart's own `$` interpolation is untouched. __ITEM__/__IPASCAL__ are not
# substrings of __NAME__/__PASCAL__, so substitution order is safe.
# Sort a Dart file's leading import directives so `directives_ordering` passes
# for ANY package name: `dart:` group, blank, `package:` group (alphabetical),
# blank, body. (dart format does not sort imports; the authored order is only
# alphabetical for some package names.)
_sort_imports() {
  local f="$1"
  grep -q '^import ' "$f" || { cat "$f"; return; }
  local darts pkgs
  # `|| true`: a no-match grep exits 1, which would trip `set -e`.
  darts="$(grep "^import 'dart:" "$f" | LC_ALL=C sort || true)"
  pkgs="$(grep '^import ' "$f" | grep -v "^import 'dart:" | LC_ALL=C sort || true)"
  [ -n "$darts" ] && printf '%s\n' "$darts"
  [ -n "$darts" ] && [ -n "$pkgs" ] && echo
  [ -n "$pkgs" ] && printf '%s\n' "$pkgs"
  echo
  grep -v '^import ' "$f" | sed '/./,$!d' || true
}

emit() {
  local dest tmp
  dest="$(printf '%s' "$1" | sed -e "s/__ITEM__/$ITEM/g" -e "s/__NAME__/$NAME/g")"
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  sed -e "s/__PKG__/$PKG/g" \
      -e "s|__IMP_RESULT__|$IMP_RESULT|g" \
      -e "s|__IMP_FAILURES__|$IMP_FAILURES|g" \
      -e "s|__IMP_ERRMAP__|$IMP_ERRMAP|g" \
      -e "s|__IMP_DI__|$IMP_DI|g" \
      -e "s/__IPASCAL__/$IPASCAL/g" \
      -e "s/__PASCAL__/$PASCAL/g" \
      -e "s/__CAMEL__/$CAMEL/g" \
      -e "s/__ITEM__/$ITEM/g" \
      -e "s/__NAME__/$NAME/g" > "$tmp"
  _sort_imports "$tmp" > "$dest"
  rm -f "$tmp"
  echo "  + $dest"
}

echo "Scaffolding '$TYPE' feature '$NAME' (item: $IPASCAL)…"

# --- UI-only ---------------------------------------------------------------
gen_ui() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class __PASCAL__Page extends StatelessWidget {
  const __PASCAL__Page({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: const Center(child: Text('TODO: __PASCAL__')),
    );
  }
}
EOF
}

# --- API-backed (full clean arch) ------------------------------------------
gen_api() {
  if [ -n "$JSON" ]; then
    # Infer entity + model (incl. nested types) from the sample response.
    python3 "$SELF_DIR/_json_to_dart.py" "$PKG" "$NAME" "$ITEM" "$JSON" "$FEATURE_DIR" \
      || { echo "error: --json generation failed" >&2; exit 1; }
  else
    cat <<'EOF' | emit "$FEATURE_DIR/domain/entities/__ITEM__.dart"
import 'package:equatable/equatable.dart';

final class __IPASCAL__ extends Equatable {
  const __IPASCAL__({required this.id});

  final int id;
  // TODO(you): add the real fields.

  @override
  List<Object?> get props => [id];
}
EOF
  fi

  cat <<'EOF' | emit "$FEATURE_DIR/domain/repositories/__NAME___repository.dart"
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';

abstract interface class __PASCAL__Repository {
  Future<Result<List<__IPASCAL__>>> getAll();
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/domain/usecases/get___NAME___use_case.dart"
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/repositories/__NAME___repository.dart';

class Get__PASCAL__UseCase {
  const Get__PASCAL__UseCase(this._repository);

  final __PASCAL__Repository _repository;

  Future<Result<List<__IPASCAL__>>> call() => _repository.getAll();
}
EOF

  if [ -z "$JSON" ]; then
    cat <<'EOF' | emit "$FEATURE_DIR/data/models/__ITEM___model.dart"
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:json_annotation/json_annotation.dart';

part '__ITEM___model.g.dart';

@JsonSerializable(createToJson: false)
class __IPASCAL__Model {
  const __IPASCAL__Model({required this.id});

  factory __IPASCAL__Model.fromJson(Map<String, dynamic> json) =>
      _$__IPASCAL__ModelFromJson(json);

  final int id;
  // TODO(you): add fields matching the API JSON (see api-contracts.md).

  __IPASCAL__ toEntity() => __IPASCAL__(id: id);
}
EOF
  fi

  cat <<'EOF' | emit "$FEATURE_DIR/data/datasources/__NAME___remote_data_source.dart"
import 'package:__PKG__/features/__NAME__/data/models/__ITEM___model.dart';

abstract interface class __PASCAL__RemoteDataSource {
  Future<List<__IPASCAL__Model>> fetchAll();
}

// TODO(you): back this with a Retrofit client (networking.md) or a fake
// datasource (feature-generation.md). The contract stays the same either way.
final class __PASCAL__RemoteDataSourceImpl implements __PASCAL__RemoteDataSource {
  const __PASCAL__RemoteDataSourceImpl();

  @override
  Future<List<__IPASCAL__Model>> fetchAll() {
    throw UnimplementedError('TODO: implement __PASCAL__RemoteDataSource.fetchAll');
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/data/repositories/__NAME___repository_impl.dart"
import 'package:dio/dio.dart';
import 'package:__PKG__/__IMP_FAILURES__';
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/__IMP_ERRMAP__';
import 'package:__PKG__/features/__NAME__/data/datasources/__NAME___remote_data_source.dart';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/repositories/__NAME___repository.dart';

final class __PASCAL__RepositoryImpl implements __PASCAL__Repository {
  const __PASCAL__RepositoryImpl(this._remoteDataSource);

  final __PASCAL__RemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<__IPASCAL__>>> getAll() async {
    try {
      final models = await _remoteDataSource.fetchAll();
      return Success(models.map((model) => model.toEntity()).toList());
    } on DioException catch (error) {
      return FailureResult(mapDioException(error));
    } on Object {
      return const FailureResult(
        UnknownFailure(message: 'common.unknown_error'),
      );
    }
  }
}
EOF

  gen_presentation

  if [ -n "$OPENAPI" ]; then
    # Overwrite the entity/model/datasource stubs with accurate types + a
    # Retrofit client generated from the spec contract.
    python3 "$SELF_DIR/_openapi_to_dart.py" "$PKG" "$NAME" "$ITEM" "$OPENAPI" \
      "$FEATURE_DIR" "$APIPATH" "$METHOD" "$STACK" \
      || { echo "error: --openapi generation failed" >&2; exit 1; }
  fi
}

# --- Presentation (branches by --stack; domain/data above are shared) --------
gen_presentation() {
  case "$STACK" in
    bloc) gen_presentation_bloc ;;
    riverpod) gen_presentation_riverpod ;;
    provider) gen_presentation_provider ;;
    getx) gen_presentation_getx ;;
    mobx) gen_presentation_mobx ;;
  esac
}

# Bloc/Cubit — the verified reference (unchanged output).
gen_presentation_bloc() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/cubit/__NAME___cubit.dart"
import 'package:equatable/equatable.dart';
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/usecases/get___NAME___use_case.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part '__NAME___state.dart';

final class __PASCAL__Cubit extends Cubit<__PASCAL__State> {
  __PASCAL__Cubit(this._getAll) : super(const __PASCAL__State());

  final Get__PASCAL__UseCase _getAll;

  Future<void> load() async {
    emit(state.copyWith(status: __PASCAL__Status.loading));
    final result = await _getAll();
    switch (result) {
      case Success(:final data):
        emit(state.copyWith(status: __PASCAL__Status.success, items: data));
      case FailureResult(:final failure):
        emit(
          state.copyWith(
            status: __PASCAL__Status.failure,
            errorMessage: failure.message,
          ),
        );
    }
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/cubit/__NAME___state.dart"
part of '__NAME___cubit.dart';

enum __PASCAL__Status { initial, loading, success, failure }

final class __PASCAL__State extends Equatable {
  const __PASCAL__State({
    this.status = __PASCAL__Status.initial,
    this.items = const [],
    this.errorMessage,
  });

  final __PASCAL__Status status;
  final List<__IPASCAL__> items;
  final String? errorMessage;

  __PASCAL__State copyWith({
    __PASCAL__Status? status,
    List<__IPASCAL__>? items,
    String? errorMessage,
  }) {
    return __PASCAL__State(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, items, errorMessage];
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:__PKG__/__IMP_DI__';
import 'package:__PKG__/features/__NAME__/presentation/cubit/__NAME___cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class __PASCAL__Page extends StatelessWidget {
  const __PASCAL__Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = getIt<__PASCAL__Cubit>();
        unawaited(cubit.load());
        return cubit;
      },
      child: const __PASCAL__View(),
    );
  }
}

class __PASCAL__View extends StatelessWidget {
  const __PASCAL__View({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: BlocBuilder<__PASCAL__Cubit, __PASCAL__State>(
        builder: (context, state) {
          switch (state.status) {
            case __PASCAL__Status.initial:
            case __PASCAL__Status.loading:
              return const Center(child: CircularProgressIndicator());
            case __PASCAL__Status.failure:
              return Center(
                child: Text(
                  (state.errorMessage ?? 'common.unknown_error').tr(),
                ),
              );
            case __PASCAL__Status.success:
              return ListView.builder(
                itemCount: state.items.length,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('#${state.items[index].id}')),
              );
          }
        },
      ),
    );
  }
}
EOF
}

# Riverpod — providers ARE the DI (no GetIt); AsyncNotifier + ConsumerWidget.
gen_presentation_riverpod() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/notifier/__NAME___notifier.dart"
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/data/datasources/__NAME___remote_data_source.dart';
import 'package:__PKG__/features/__NAME__/data/repositories/__NAME___repository_impl.dart';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/repositories/__NAME___repository.dart';
import 'package:__PKG__/features/__NAME__/domain/usecases/get___NAME___use_case.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part '__NAME___notifier.g.dart';

// DI as providers (no get_it). Swap the datasource for a Retrofit-backed impl.
@riverpod
__PASCAL__RemoteDataSource __CAMEL__RemoteDataSource(Ref ref) =>
    const __PASCAL__RemoteDataSourceImpl();

@riverpod
__PASCAL__Repository __CAMEL__Repository(Ref ref) =>
    __PASCAL__RepositoryImpl(ref.watch(__CAMEL__RemoteDataSourceProvider));

@riverpod
Get__PASCAL__UseCase get__PASCAL__UseCase(Ref ref) =>
    Get__PASCAL__UseCase(ref.watch(__CAMEL__RepositoryProvider));

@riverpod
class __PASCAL__Notifier extends _$__PASCAL__Notifier {
  @override
  Future<List<__IPASCAL__>> build() => _fetch();

  Future<List<__IPASCAL__>> _fetch() async {
    final result = await ref.read(get__PASCAL__UseCaseProvider)();
    return switch (result) {
      Success(:final data) => data,
      FailureResult(:final failure) => throw failure,
    };
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'package:easy_localization/easy_localization.dart';
import 'package:__PKG__/__IMP_FAILURES__';
import 'package:__PKG__/features/__NAME__/presentation/notifier/__NAME___notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class __PASCAL__Page extends ConsumerWidget {
  const __PASCAL__Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(__CAMEL__Provider);
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            (e is AppFailure ? e.message : 'common.unknown_error').tr(),
          ),
        ),
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) =>
              ListTile(title: Text('#${items[index].id}')),
        ),
      ),
    );
  }
}
EOF
}

# Provider — ChangeNotifier + GetIt for DI.
gen_presentation_provider() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/notifier/__NAME___notifier.dart"
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/usecases/get___NAME___use_case.dart';
import 'package:flutter/foundation.dart';

enum __PASCAL__Status { initial, loading, success, failure }

class __PASCAL__Notifier extends ChangeNotifier {
  __PASCAL__Notifier(this._getAll);

  final Get__PASCAL__UseCase _getAll;

  __PASCAL__Status status = __PASCAL__Status.initial;
  List<__IPASCAL__> items = const [];
  String? errorMessage;

  Future<void> load() async {
    status = __PASCAL__Status.loading;
    errorMessage = null;
    notifyListeners();
    final result = await _getAll();
    switch (result) {
      case Success(:final data):
        items = data;
        status = __PASCAL__Status.success;
      case FailureResult(:final failure):
        errorMessage = failure.message;
        status = __PASCAL__Status.failure;
    }
    notifyListeners();
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:__PKG__/__IMP_DI__';
import 'package:__PKG__/features/__NAME__/presentation/notifier/__NAME___notifier.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class __PASCAL__Page extends StatelessWidget {
  const __PASCAL__Page({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final notifier = getIt<__PASCAL__Notifier>();
        unawaited(notifier.load());
        return notifier;
      },
      child: const __PASCAL__View(),
    );
  }
}

class __PASCAL__View extends StatelessWidget {
  const __PASCAL__View({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: Consumer<__PASCAL__Notifier>(
        builder: (context, n, _) {
          switch (n.status) {
            case __PASCAL__Status.initial:
            case __PASCAL__Status.loading:
              return const Center(child: CircularProgressIndicator());
            case __PASCAL__Status.failure:
              return Center(
                child: Text((n.errorMessage ?? 'common.unknown_error').tr()),
              );
            case __PASCAL__Status.success:
              return ListView.builder(
                itemCount: n.items.length,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('#${n.items[index].id}')),
              );
          }
        },
      ),
    );
  }
}
EOF
}

# GetX — state only (GetxController + Obx); GetIt for DI, go_router for routing.
gen_presentation_getx() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/controller/__NAME___controller.dart"
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/usecases/get___NAME___use_case.dart';
import 'package:get/get.dart';

enum __PASCAL__Status { initial, loading, success, failure }

class __PASCAL__Controller extends GetxController {
  __PASCAL__Controller(this._getAll);

  final Get__PASCAL__UseCase _getAll;

  final Rx<__PASCAL__Status> status = __PASCAL__Status.initial.obs;
  final RxList<__IPASCAL__> items = <__IPASCAL__>[].obs;
  final RxnString errorMessage = RxnString();

  Future<void> load() async {
    status.value = __PASCAL__Status.loading;
    errorMessage.value = null;
    final result = await _getAll();
    switch (result) {
      case Success(:final data):
        items.assignAll(data);
        status.value = __PASCAL__Status.success;
      case FailureResult(:final failure):
        errorMessage.value = failure.message;
        status.value = __PASCAL__Status.failure;
    }
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'package:easy_localization/easy_localization.dart';
import 'package:__PKG__/__IMP_DI__';
import 'package:__PKG__/features/__NAME__/presentation/controller/__NAME___controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Trans;

class __PASCAL__Page extends StatefulWidget {
  const __PASCAL__Page({super.key});

  @override
  State<__PASCAL__Page> createState() => _PageState();
}

class _PageState extends State<__PASCAL__Page> {
  late final __PASCAL__Controller _controller = getIt<__PASCAL__Controller>()
    ..load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: Obx(() {
        switch (_controller.status.value) {
          case __PASCAL__Status.initial:
          case __PASCAL__Status.loading:
            return const Center(child: CircularProgressIndicator());
          case __PASCAL__Status.failure:
            return Center(
              child: Text(
                (_controller.errorMessage.value ?? 'common.unknown_error').tr(),
              ),
            );
          case __PASCAL__Status.success:
            return ListView.builder(
              itemCount: _controller.items.length,
              itemBuilder: (context, index) =>
                  ListTile(title: Text('#${_controller.items[index].id}')),
            );
        }
      }),
    );
  }
}
EOF
}

# MobX — Store + Observer; GetIt added for DI; build_runner generates the store.
gen_presentation_mobx() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/store/__NAME___store.dart"
import 'package:__PKG__/__IMP_RESULT__';
import 'package:__PKG__/features/__NAME__/domain/entities/__ITEM__.dart';
import 'package:__PKG__/features/__NAME__/domain/usecases/get___NAME___use_case.dart';
import 'package:mobx/mobx.dart';

part '__NAME___store.g.dart';

enum __PASCAL__Status { initial, loading, success, failure }

// The `Store = _StoreBase with _$Store` typedef is the standard MobX pattern;
// referencing the private base in the public typedef is intentional.
// ignore: library_private_types_in_public_api
class __PASCAL__Store = ___PASCAL__Store with _$__PASCAL__Store;

abstract class ___PASCAL__Store with Store {
  ___PASCAL__Store(this._getAll);

  final Get__PASCAL__UseCase _getAll;

  @observable
  __PASCAL__Status status = __PASCAL__Status.initial;

  @observable
  ObservableList<__IPASCAL__> items = ObservableList<__IPASCAL__>();

  @observable
  String? errorMessage;

  @action
  Future<void> load() async {
    status = __PASCAL__Status.loading;
    errorMessage = null;
    final result = await _getAll();
    switch (result) {
      case Success(:final data):
        items = ObservableList.of(data);
        status = __PASCAL__Status.success;
      case FailureResult(:final failure):
        errorMessage = failure.message;
        status = __PASCAL__Status.failure;
    }
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'package:easy_localization/easy_localization.dart';
import 'package:__PKG__/__IMP_DI__';
import 'package:__PKG__/features/__NAME__/presentation/store/__NAME___store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class __PASCAL__Page extends StatefulWidget {
  const __PASCAL__Page({super.key});

  @override
  State<__PASCAL__Page> createState() => _PageState();
}

class _PageState extends State<__PASCAL__Page> {
  late final __PASCAL__Store _store = getIt<__PASCAL__Store>()..load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: Observer(
        builder: (context) {
          switch (_store.status) {
            case __PASCAL__Status.initial:
            case __PASCAL__Status.loading:
              return const Center(child: CircularProgressIndicator());
            case __PASCAL__Status.failure:
              return Center(
                child: Text((_store.errorMessage ?? 'common.unknown_error').tr()),
              );
            case __PASCAL__Status.success:
              return ListView.builder(
                itemCount: _store.items.length,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('#${_store.items[index].id}')),
              );
          }
        },
      ),
    );
  }
}
EOF
}

# --- API command (POST / PUT / PATCH / DELETE) ------------------------------
# The engine generates everything from the spec: request entity/model (toJson +
# fromEntity), optional response entity/model, the Retrofit client (verb + @Path
# + @Body), datasource, repo, use case, and a Bloc command cubit (v1).
gen_api_command() {
  python3 "$SELF_DIR/_openapi_to_dart.py" "$PKG" "$NAME" "$ITEM" "$OPENAPI" \
    "$FEATURE_DIR" "$APIPATH" "$METHOD" "$STACK" \
    || { echo "error: --openapi $METHOD generation failed" >&2; exit 1; }
}


# --- Form ------------------------------------------------------------------
gen_form() {
  cat <<'EOF' | emit "$FEATURE_DIR/presentation/cubit/__NAME___cubit.dart"
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part '__NAME___state.dart';

final class __PASCAL__Cubit extends Cubit<__PASCAL__State> {
  __PASCAL__Cubit() : super(const __PASCAL__State());

  // TODO(you): inject a use case and call it from submit().
  Future<void> submit() async {
    emit(state.copyWith(isSubmitting: true));
    // TODO(you): await the use case, then emit success or failure.
    emit(state.copyWith(isSubmitting: false, isSuccess: true));
  }
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/cubit/__NAME___state.dart"
part of '__NAME___cubit.dart';

final class __PASCAL__State extends Equatable {
  const __PASCAL__State({
    this.isSubmitting = false,
    this.isSuccess = false,
    this.errorMessage,
  });

  final bool isSubmitting;
  final bool isSuccess;
  final String? errorMessage;

  __PASCAL__State copyWith({
    bool? isSubmitting,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return __PASCAL__State(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [isSubmitting, isSuccess, errorMessage];
}
EOF

  cat <<'EOF' | emit "$FEATURE_DIR/presentation/pages/__NAME___page.dart"
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:__PKG__/__IMP_DI__';
import 'package:__PKG__/features/__NAME__/presentation/cubit/__NAME___cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class __PASCAL__Page extends StatelessWidget {
  const __PASCAL__Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<__PASCAL__Cubit>(),
      child: const __PASCAL__View(),
    );
  }
}

class __PASCAL__View extends StatefulWidget {
  const __PASCAL__View({super.key});

  @override
  State<__PASCAL__View> createState() => _Form__PASCAL__State();
}

class _Form__PASCAL__State extends State<__PASCAL__View> {
  final _formKey = GlobalKey<FormState>();
  final _fieldController = TextEditingController();

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      unawaited(context.read<__PASCAL__Cubit>().submit());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('__NAME__.title'.tr())),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _fieldController,
                decoration: InputDecoration(labelText: '__NAME__.field'.tr()),
                validator: (value) =>
                    (value == null || value.isEmpty) ? '__NAME__.required'.tr() : null,
              ),
              const SizedBox(height: 24),
              BlocBuilder<__PASCAL__Cubit, __PASCAL__State>(
                builder: (context, state) => FilledButton(
                  onPressed: state.isSubmitting ? null : _submit,
                  child: Text('__NAME__.submit'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
EOF
}

case "$TYPE" in
  ui) gen_ui ;;
  api) if [ "$IS_COMMAND" = "1" ]; then gen_api_command; else gen_api; fi ;;
  form) gen_form ;;
esac

# --- FINAL / FILL classification -------------------------------------------
# So the agent doesn't re-open generated files to check them: a file with NO
# 'TODO(you)' marker is complete; a file WITH one needs hand-work. Derived from
# actual contents, so it stays correct across ui/api/form, --json/--openapi/stub,
# and every --stack (stub mode puts the entity/model in FILL — they carry TODOs).
_FINAL=""; _FILL=""
while IFS= read -r _f; do
  [ -z "$_f" ] && continue
  if grep -qF 'TODO(you)' "$_f" 2>/dev/null; then
    _FILL="$_FILL  $_f"$'\n'
  else
    _FINAL="$_FINAL  $_f"$'\n'
  fi
done <<EOF
$(find "$FEATURE_DIR" -type f -name '*.dart' | LC_ALL=C sort)
EOF
echo
echo "FINAL — complete, do not open:"
[ -n "$_FINAL" ] && printf '%s' "$_FINAL" || echo "  (none)"
echo "FILL — contains TODO(you), open only these:"
[ -n "$_FILL" ] && printf '%s' "$_FILL" || echo "  (none)"

# --- follow-ups ------------------------------------------------------------
echo
echo "Done. Next (the parts that carry real logic):"
case "$TYPE" in
  ui)
    echo "  • Add '$NAME.title' to assets/lang/*.json."
    echo "  • Add a route to ${PASCAL}Page in core/router."
    ;;
  api)
    if [ "$IS_COMMAND" = "1" ]; then
      SUF=""
      case "$METHOD" in
        post) UCP=Submit; MN=submit ;;
        put) UCP=Update; MN=update ;;
        patch) UCP=Patch; MN=patch ;;
        delete) UCP=Delete; MN=delete ;;
        get) UCP=Get; MN=getById; SUF=ById ;;
      esac
      # Per-stack presentation holder + a human label (mirrors the GET branch).
      case "$STACK" in
        bloc)     CHOLDER="${PASCAL}Cubit";      SDESC="a Bloc cubit" ;;
        riverpod) CHOLDER="${PASCAL}";           SDESC="a Riverpod notifier" ;;
        provider) CHOLDER="${PASCAL}Notifier";   SDESC="a ChangeNotifier" ;;
        getx)     CHOLDER="${PASCAL}Controller"; SDESC="a GetX controller" ;;
        mobx)     CHOLDER="${PASCAL}Store";      SDESC="a MobX store" ;;
      esac
      if [ "$METHOD" = "get" ]; then
        WIRE="navigate to ${PASCAL}Page(id: ...) — it loads on open"
      else
        WIRE="wire ${PASCAL}Page's button to trigger the ${MN} on ${CHOLDER}"
      fi
      cat <<NOTE
  • ${METHOD} from the spec: entity + model, Retrofit ${PASCAL}Api (the ${METHOD}
    endpoint with @Path/@Body as needed), a Dio-backed datasource,
    ${PASCAL}Repository.${MN} + ${UCP}${PASCAL}${SUF}UseCase, and ${SDESC}.
  • ${WIRE}.
NOTE
      if [ "$STACK" = "riverpod" ]; then
        cat <<NOTE
  • DI is providers (already generated in the notifier file) — no GetIt. Ensure
    the app is wrapped in ProviderScope; the page reads ${CAMEL}Provider and
    calls ref.read(${CAMEL}Provider.notifier) for the ${MN}.
NOTE
      else
        cat <<NOTE
  • Register in $IMP_DI (ensure a Dio is registered):
      ..registerLazySingleton<${PASCAL}RemoteDataSource>(
        () => ${PASCAL}RemoteDataSourceImpl(getIt<Dio>()),
      )
      ..registerLazySingleton<${PASCAL}Repository>(
        () => ${PASCAL}RepositoryImpl(getIt<${PASCAL}RemoteDataSource>()),
      )
      ..registerLazySingleton(() => ${UCP}${PASCAL}${SUF}UseCase(getIt<${PASCAL}Repository>()))
      ..registerFactory(() => ${CHOLDER}(getIt<${UCP}${PASCAL}${SUF}UseCase>()))
NOTE
      fi
      cat <<NOTE
  • Add '$NAME.title' / '$NAME.submit' / '$NAME.success' to assets/lang/*.json
    and a route to ${PASCAL}Page.
  • Run: dart run build_runner build --delete-conflicting-outputs
  • Run: scripts/check_layers.sh && flutter analyze
NOTE
    else
    if [ -n "$OPENAPI" ]; then
      cat <<NOTE
  • Generated from the OpenAPI spec: accurate entity/model (incl. nested types;
    enums as String), the Retrofit client ${PASCAL}Api (@GET '$APIPATH'), and a
    Dio-backed ${PASCAL}RemoteDataSource. Review nullability; set the Dio baseUrl
    where the Dio is created/registered.
NOTE
    elif [ -n "$JSON" ]; then
      cat <<NOTE
  • Review the inferred entity/model: id kept required, other fields nullable,
    plus any "looks like a date" / "type unknown" TODO hints.
  • Write the Retrofit client + datasource impl (the sample can't give the
    verb/path/envelope) for ${PASCAL}RemoteDataSource — see networking.md.
NOTE
    else
      cat <<NOTE
  • Fill the real fields on the entity + model (ask for the API JSON first),
    or re-run with --json <file> to infer them.
  • Implement ${PASCAL}RemoteDataSource (Retrofit client or fake datasource).
NOTE
    fi
    case "$STACK" in
      bloc) HOLDER="${PASCAL}Cubit" ;;
      provider) HOLDER="${PASCAL}Notifier" ;;
      getx) HOLDER="${PASCAL}Controller" ;;
      mobx) HOLDER="${PASCAL}Store" ;;
      riverpod) HOLDER="" ;;
    esac
    if [ "$STACK" = "riverpod" ]; then
      cat <<NOTE
  • DI is providers (already generated in the notifier file) — no GetIt. Ensure
    the app is wrapped in ProviderScope; the page reads ${CAMEL}Provider.
NOTE
    else
      if [ -n "$OPENAPI" ]; then
        DSREG="() => ${PASCAL}RemoteDataSourceImpl(getIt<Dio>())"
        DIONOTE="      // ensure a Dio is registered, e.g.
      // ..registerLazySingleton(() => Dio(BaseOptions(baseUrl: Env.baseUrl)))
"
      else
        DSREG="() => const ${PASCAL}RemoteDataSourceImpl()"
        DIONOTE=""
      fi
      cat <<NOTE
  • Register the chain in $IMP_DI:
$DIONOTE      ..registerLazySingleton<${PASCAL}RemoteDataSource>($DSREG)
      ..registerLazySingleton<${PASCAL}Repository>(
        () => ${PASCAL}RepositoryImpl(getIt<${PASCAL}RemoteDataSource>()),
      )
      ..registerLazySingleton(() => Get${PASCAL}UseCase(getIt<${PASCAL}Repository>()))
      ..registerFactory(() => ${HOLDER}(getIt<Get${PASCAL}UseCase>()))
NOTE
    fi
    cat <<NOTE
  • Add '$NAME.title' to assets/lang/*.json and a route to ${PASCAL}Page.
  • Run: dart run build_runner build --delete-conflicting-outputs
  • Run: scripts/check_layers.sh && flutter analyze
NOTE
    fi
    ;;
  form)
    cat <<NOTE
  • Wire a use case into ${PASCAL}Cubit.submit() (inject via constructor).
  • Register in $IMP_DI:
      ..registerFactory(() => ${PASCAL}Cubit(/* deps */))
  • Add '$NAME.title', '$NAME.field', '$NAME.required', '$NAME.submit' to
    assets/lang/*.json and a route to ${PASCAL}Page.
NOTE
    ;;
esac
