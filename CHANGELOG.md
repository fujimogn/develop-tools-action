# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.5] - 2026-10-25

### Changed

- The bundled resolver and `platform-check.yml` no longer read a root `.develop-tools.json`. A file left only at that path fails and names `.config/develop-tools.json` as the place to move it. Both files still fail.

## [0.3.4] - 2026-10-25

### Fixed

- Fix the v0.3.3 macOS Bun version resolver on runner Python without `tomllib`.

## [0.3.3] - 2026-10-25

### Changed

- `platform-check.yml`: when `platformCheck.bun` is true, resolve Bun from `.config/mise.toml` `[tools].bun` first and from `.tool-versions` only when that mise file is absent. A broken or non-pinned mise value stops the job, and the two versions must match when both exist. The published version is unchanged.
- README and the `platform-check.yml` header now name `.config/develop-tools.json` as the manifest location; the legacy root `.develop-tools.json` is still read.

## [0.3.2] - 2026-10-23

### Added

- Look for the manifest at `.config/develop-tools.json` first and at `.develop-tools.json` second, in both `platform-check.yml` (unless the caller sets `MANIFEST`) and the bundled resolver. Each one fails when both files exist.

## [0.3.1] - 2026-10-21

### Added

- `platform-check.yml`: `platformCheck.cargoWorkspace` takes one path or a list of paths, and `platformCheck.runIgnored` runs the ignored tests a nextest filterset matches.

## [0.3.0] - 2026-10-21

### Added

- Reusable workflow `platform-check.yml` that builds and tests the caller's Cargo workspace on every OS declared in `.develop-tools.json` (`platforms`: `linux`, `macos`, `windows`). An invalid declaration fails the plan job, and no OS check runs without a declaration.

### Changed

- Install checksum-pinned public release binaries without a caller-provided token. The bundled resolver returns the verified bin directory without running a tool during installation.

## [0.2.0] - 2026-10-18

### Changed

- Continue the action after 1.0.x under a 0.x version: patch for changes callers can adopt without adjustment, minor when callers must adjust, and major only after an explicit stability declaration.
- Document a commit-SHA-pinned `v0.2.0` example. The published 1.0.x tags and the working `v1` tag remain at their existing commits.

## [1.0.2] - 2026-10-13

### Changed

- Download the release with one `gh release download` call instead of three sequential `gh api` calls. Most of the gain comes from making one call instead of three, not from fetching the two assets concurrently. In 10 paired runs on a local machine against the real release, the install took a median 0.7 s less; the saving on GitHub-hosted runners has not been measured yet.

### Fixed

- Retry a failed release download up to three attempts, five seconds apart, so a transient GitHub error no longer fails the step (seen once on a child repository, where a rerun passed).

## [1.0.1] - 2026-10-12

### Fixed

- Tests use `grep` instead of `rg`, which GitHub-hosted runners do not provide; a missing `rg` had let the token-leak check pass silently.

## [1.0.0] - 2026-10-12

### Added

- Composite action to install manifest-pinned Linux x86_64 develop tools from a private GitHub Release using a caller-provided token.
- Verification against the committed SHA256 and release checksum list before installation.
- Offline fixture tests and CI for successful installation, checksum rejection, and token-free logs.
