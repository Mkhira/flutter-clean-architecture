# Auth and Secure Storage

Recommended package when auth exists:

```yaml
flutter_secure_storage: latest-compatible
```

## Rules

- Store access/refresh tokens in secure storage, **not** HydratedBloc.
- HydratedBloc may store non-sensitive app state only.
- The auth interceptor may attach the access token.
- The refresh token flow must be explicit and safe (avoid races; queue or lock
  concurrent refreshes).
- On logout, clear tokens, user session cache, relevant DI scopes if used, and
  any hydrated auth state.
- Never log tokens.
- Ask the user/backend contract for token field names and the refresh endpoint.

## Ask before implementing auth (if unknown)

```text
login request body
login success response
refresh token endpoint
refresh request body
refresh response body
logout endpoint if any
token expiration behavior
```

## Secure storage rules

- Hide the storage implementation behind an abstraction.
- Keep storage in data/core infrastructure, not UI.
- Do not expose raw token values outside auth/network infrastructure unless
  required.

## Gating screens on auth state

Storing tokens is only half the job — the router must redirect based on auth
state. Wire `GoRouter`'s `redirect` + `refreshListenable` to the auth Bloc's
stream so navigation re-evaluates the instant a token changes (login, logout,
expiry). See the **"Auth-gated navigation"** section in `routing.md` for the
`redirect` guard and the `GoRouterRefreshStream` bridge. Keep auth *state* in the
Bloc; the router only reads it.
