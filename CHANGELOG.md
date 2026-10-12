# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Composite action to install manifest-pinned Linux x86_64 develop tools from a private GitHub Release using a caller-provided token.
- Verification against the committed SHA256 and release checksum list before installation.
- Offline fixture tests and CI for successful installation, checksum rejection, and token-free logs.
