# API Contracts

This file is critical. **Do not invent backend JSON models.**

## Rule

Before generating Dio/Retrofit methods or request/response models, ask for API
contracts unless they are already discoverable in the repo, docs, tests, or
OpenAPI/Postman.

**Prefer an OpenAPI/Swagger spec when one exists.** It's a contract, not a
sample, so the generator can produce exact types **and** the Retrofit client:
`scripts/new_feature.sh api <name> --item <s> --openapi <spec.json> --path
<endpoint>` (see `feature-generation.md`). A sample JSON (`--json`) is the
fallback when there's no spec — it infers the model but can't write the client.

Ask the user for:

```text
sample JSON response
sample POST/PUT/PATCH request body
sample error response
Swagger/OpenAPI URL or file
Postman collection
existing backend contract
```

Example prompt:

```text
Please send the request body and response JSON for this endpoint so I can create
the Retrofit method and models correctly.
```

If the user asks for a login API, ask for:

```text
login request JSON
success response JSON
failure response JSON
token fields and refresh behavior
```

If examples already exist in repo docs/tests/OpenAPI, use them and do not ask.

Do not invent field names or model shapes.

## When the API has request and response bodies

- Create the request model from the provided request JSON.
- Create the response model from the provided response JSON.
- Create an error model only when useful and the API contract provides it.
- Add `@JsonSerializable()`.
- Add `part '<file>.g.dart';`.
- Run build_runner after changes.

## Nested objects

- Create nested models when they are meaningful or reused.
- Keep tiny one-off nested objects inline only if project convention allows.

## Lists

- Model the item type explicitly.
- Avoid `List<dynamic>` at data/domain boundaries.
