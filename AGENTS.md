# Contributing guidance

- Keep the action focused on reading `.develop-tools.json`, authenticated release downloads, checksum verification, and PATH setup.
- Never include credentials or print tokens, API response bodies, or authentication diagnostics.
- Preserve the manifest format within a major action version.
- Use offline fixtures for tests; do not contact GitHub or require real credentials.
- Run `bash tests/run.sh` and shell syntax validation before committing changes.
- Keep documentation in English and update `CHANGELOG.md` for user-visible changes.
