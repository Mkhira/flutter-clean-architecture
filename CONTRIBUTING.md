# Contributing

Thanks for your interest in improving the Flutter Clean Architecture skill.

## Repo layout

```
.claude-plugin/        plugin + marketplace manifests
skills/
└── flutter-clean-architecture/
    ├── SKILL.md        the skill's behavior (authoritative)
    ├── references/     topic docs loaded on demand
    ├── scripts/        generators & validators
    └── assets/         default-scaffold templates
```

The published skill is everything under `skills/flutter-clean-architecture/`.
The `eval/` harness is local-only (git-ignored) and not part of the package.

## Reporting issues

Open a GitHub issue with:

- what you asked the skill to do,
- the agent and Flutter/Dart versions you're on,
- what happened vs. what you expected.

## Pull requests

- Keep the dependency rule intact — `domain/` stays pure Dart, `presentation/`
  never imports `data/`.
- Match the existing style of the references and scripts.
- If you change a generator, run the eval harness locally before opening the PR.
- Note user-facing changes in `CHANGELOG.md`.

## License

By contributing you agree your contributions are licensed under the
[MIT License](LICENSE).
