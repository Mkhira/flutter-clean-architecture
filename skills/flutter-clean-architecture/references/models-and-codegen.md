# Models and Codegen

Use JsonSerializable for DTOs/models.

## Example

```dart
import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable()
class UserModel {
  const UserModel({
    required this.id,
    required this.name,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  final int id;
  final String name;

  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}
```

## Rules

- Data models live in the data layer.
- Domain entities live in the domain layer.
- Models may extend/convert to entities only if project convention allows.
- Prefer explicit mapping methods such as `toEntity()`.
- Use `@JsonKey(name: 'api_field')` for renamed fields.
- Use custom converters for unsupported types.
- Never edit `.g.dart` or `.freezed.dart` manually.

## Conditional build_runner

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

only after creating/editing:

```text
@JsonSerializable classes
@RestApi interfaces
@Envied classes
@freezed/@Freezed classes
part '*.g.dart'
part '*.freezed.dart'
build.yaml generator config
```

Do not run build_runner for normal UI, Cubit, Bloc, repository logic, use cases,
tests, or theme edits unless generated-code inputs changed.

> **build_runner 2.15+** removed the `--delete-conflicting-outputs` flag and now
> ignores it with a harmless warning (`These options have been removed and were
> ignored: --delete-conflicting-outputs`). Keep passing it — it is still required
> by older build_runner versions and is safe on newer ones.

## Freezed

- Use Freezed for complex unions and immutable models when available/appropriate.
- Do not add Freezed to an existing project unless useful and approved or already
  used.
- When using Freezed with JSON, include both parts:

  ```dart
  part 'model.freezed.dart';
  part 'model.g.dart';
  ```
