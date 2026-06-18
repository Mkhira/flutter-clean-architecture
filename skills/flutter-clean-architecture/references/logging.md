# Logging

## Optional packages

```yaml
logger: latest-compatible
pretty_dio_logger: latest-compatible
```

## Rules

- Logging only in debug/dev flavor.
- Never log Authorization headers, tokens, passwords, OTPs, personal data, or
  full sensitive response bodies.
- Dio `LogInterceptor` or a pretty logger must redact sensitive fields.
- In production, disable verbose network logging.
- Use structured logs where useful.
- Technical logs are not user-facing errors.

## Sensitive keys to redact

```text
authorization
access_token
refresh_token
token
password
otp
secret
api_key
```
