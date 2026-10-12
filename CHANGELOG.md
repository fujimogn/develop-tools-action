# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
