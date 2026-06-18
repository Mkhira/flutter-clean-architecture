# Connectivity

## Optional packages

```yaml
connectivity_plus: latest-compatible
internet_connection_checker_plus: latest-compatible
```

## Rules

- Add connectivity packages only if the feature needs network awareness.
- Connectivity type does not guarantee internet access.
- Use an internet checker for actual reachability if needed.
- Repositories should still handle network failures even if connectivity is
  checked.
- UI should show localized retry/offline messages.

Do not block all networking only because connectivity status is unknown. Always
handle request failures.
