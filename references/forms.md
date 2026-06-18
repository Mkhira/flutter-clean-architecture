# Forms

## Default

- Use simple Cubit validation for small forms.
- Use `formz` for complex reusable form validation if added/available.
- Keep validation logic out of widgets.
- Show localized error messages.
- Prevent duplicate submits with Cubit state or Bloc `droppable()`.

## Login form states

```text
idle
validating
submitting
success
failure
```

Do not call the API directly from button handlers; send the intention to
Cubit/Bloc.

## Rules

- `TextEditingController`s belong in widgets or form controllers, not the Cubit
  unless project convention says otherwise.
- The Cubit stores validated values and submission state, not widget objects.
- Validation messages must use localization keys.
- Disable submit while submitting.
- Do not trigger duplicate network calls.
