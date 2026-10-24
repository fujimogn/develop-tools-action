# develop-tools-action

Install checksum-pinned binaries from the public [`fujimogn/develop-tools`](https://github.com/fujimogn/develop-tools) Release. The action uses its bundled `resolve` script to check the version and SHA256 in the calling repository's `.develop-tools.json`; it does not need a token. Linux x86_64 and macOS arm64 are supported.

After checking out the repository, pin this action to a full commit SHA:

```yaml
- name: Install develop tools
  uses: fujimogn/develop-tools-action@<published-commit-sha>
```

Commit `.config/develop-tools.json` (the legacy root `.develop-tools.json` is still read when `.config/` has none). Its `version` selects a `v<version>` Release, and `sha256` pins each target's archive:

```json
{
  "version": "0.6.0",
  "sha256": {
    "x86_64-unknown-linux-gnu": "<64 lowercase hexadecimal characters>",
    "aarch64-apple-darwin": "<64 lowercase hexadecimal characters>"
  }
}
```

The resolver fetches the matching archive and `SHA256SUMS` from the public Release, verifies both checksums, and caches the verified binaries. The action adds that cache directory to `GITHUB_PATH` for later steps. A missing asset or checksum mismatch fails the step. Set `DEVELOP_TOOLS_BIN_DIR` to use an existing local directory instead.

The action version controls the installation procedure independently of the tool version in `.config/develop-tools.json`. Replace `<published-commit-sha>` with the full SHA of the published action commit before distributing a workflow. Existing action tags remain at their historical commits.

## Platform check

`.github/workflows/platform-check.yml` is a reusable workflow that builds and tests the Cargo workspaces on each OS the calling repository declares. Call it from a job, pinned to a full commit SHA:

```yaml
jobs:
  platforms:
    uses: fujimogn/develop-tools-action/.github/workflows/platform-check.yml@<published-commit-sha>
```

Declare the OS list and the check in `.config/develop-tools.json`:

```json
{
  "platforms": ["linux", "macos"],
  "platformCheck": {
    "cargoWorkspace": ["tools", "packages/cli"],
    "bun": true,
    "setup": "./bin/ci-install --frozen-lockfile",
    "runIgnored": "kind(lib) | kind(bin)"
  },
  "release": { "preflightWorkflow": "ci.yml" }
}
```

- `platforms`: a non-empty list of `linux`, `macos` and `windows` without duplicates. Without it the workflow starts no OS job. `release.preflightWorkflow` is required with it.
- `platformCheck.cargoWorkspace`: the workspace path relative to the repository root, `/`-separated, without `.` or `..` segments, a leading or trailing `/`, `\` or `:` (no drive letters), or a non-empty list of such paths without duplicates. Every step runs in each workspace, which keeps its own target directory. Defaults to `.`.
- `platformCheck.bun`: install Bun before the tests. The version comes from `.config/mise.toml` `[tools].bun` (a fixed `x.y.z` string) when that file exists, and from `.tool-versions` only when it does not. When both declare `bun`, the versions must match. A mise file that exists but cannot be read, or whose `bun` value is not a fixed `x.y.z`, stops the job. Defaults to `false`.
- `platformCheck.setup`: a command run with bash from the repository root before the tests.
- `platformCheck.runIgnored`: a nextest filterset. After the regular tests, the ignored tests it matches run as well (`--run-ignored only`); a workspace with no match passes. Without it no ignored test runs.

Each OS runs as a job named `platform (<os>)` (seen as `<caller job> / platform (<os>)` in the caller's run) with clippy, a release build, nextest, the declared ignored tests and doc tests. Jobs do not stop each other on failure.

## Development

Run `bash tests/run.sh` (requires `jq`) for the offline action and platform-check contract tests and `sh -n resolve` for resolver syntax after the resolver copy is added. The `resolve` file is copied byte for byte from the source in develop-tools.

## License

[MIT](LICENSE).
