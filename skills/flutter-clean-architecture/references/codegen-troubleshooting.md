# Codegen Troubleshooting (build_runner)

`build_runner` failures are the most common scaffold blocker. "Use latest
compatible versions" is the right policy, but when latest *isn't* compatible the
agent must diagnose deliberately instead of flailing — blind retries quietly burn
a lot of tokens.

## First rule: read the FIRST error, not the cascade

build_runner prints a long failure cascade; the actionable cause is almost always
the **first** error, and the rest are downstream noise. Scroll up to the first
`[SEVERE]` / `Error running ...` line and act on that. Don't react to the last
screenful.

```bash
# Surface the first real error quickly:
dart run build_runner build 2>&1 | grep -nE "\[SEVERE\]|Error|error:" | head -20
```

## The three buckets (in order of likelihood)

### 1. Version mismatch — a generator vs analyzer/source_gen

Symptoms: `Because <pkg> depends on analyzer ^X and ...`, or version solving fails
when you add the codegen + test dev-deps together. The Flutter SDK pins
`analyzer`/`test_api`/`matcher` (via `flutter_test`), and a too-new generator (or
too-new leaf annotation package) can't fit.

Playbook:
- Add dev-deps in **groups**, not all at once, so the offending package is obvious.
- **Pin/relax the offending leaf**, not the whole stack. The classic case:
  `flutter pub add json_annotation` grabs the newest (e.g. `^4.12.0`) but the
  resolvable `json_serializable` only allows `>=4.11.0 <4.12.0` → relax
  `json_annotation` to `^4.11.0` and `pub get`. (See `package-stack.md`.)
- **Never** hand-pin `analyzer` / `test_api` / `matcher` to force a solution —
  that fights the SDK's own constraints and breaks `flutter test`.
- Confirm the known pairings: `retrofit_generator`↔`retrofit`,
  `envied_generator`↔`envied`, `bloc_test` major ↔ `bloc` major.

### 2. Stale / conflicting outputs

Symptoms: `Conflicting outputs were detected`, or edits don't regenerate, or a
`.g.dart` references a field you renamed/removed.

Playbook (cheap → nuclear):
```bash
dart run build_runner build --delete-conflicting-outputs
# still stale? clear the build cache and regenerate:
dart run build_runner clean
flutter clean
rm -rf .dart_tool/build
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```
> build_runner 2.15+ removed `--delete-conflicting-outputs` and ignores it with a
> harmless warning; keep passing it for older versions.

### 3. Malformed annotation / part directive

Symptoms: a misleading, wide failure ("nothing generated", or an error pointing at
an unrelated file) caused by one bad input — the builder aborts the whole run.

Checklist:
- Every codegen file has the matching `part '<name>.g.dart';` (and
  `part '<name>.freezed.dart';` for Freezed) — exact filename, no typo.
- The annotation is well-formed (`@JsonSerializable()`, `@RestApi()`, `@Envied(...)`),
  imported, and on a class that matches the generator's expectations.
- For Retrofit: the `factory X(Dio dio, {String? baseUrl}) = _X;` line matches the
  `part` name.
- For Envied: the `.env` file referenced by `path:` exists.
- A single offending file can fail the whole build — bisect by reverting the most
  recently edited codegen input.

## Don't loop

If two distinct fixes from the right bucket don't resolve it, stop and report the
**first** error verbatim plus what was tried — don't keep re-running `build` hoping
it changes. Repeated blind builds are the main token sink here.
