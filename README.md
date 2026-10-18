# develop-tools-action

Install checksum-pinned develop tools from the private `fujimogn/develop-meta` GitHub Release. The action supports Linux x86_64 runners and requires Bash, GitHub CLI (`gh`), `jq`, Python 3, and `sha256sum`, available on GitHub-hosted Ubuntu runners.

After checking out your repository, use these two steps:

```yaml
- name: Create release reader token
  id: develop-tools-token
  uses: actions/create-github-app-token@v2
  with:
    app-id: ${{ vars.DEVELOP_TOOLS_APP_ID }}
    private-key: ${{ secrets.DEVELOP_TOOLS_APP_PRIVATE_KEY }}
    owner: fujimogn
    repositories: develop-meta
    permission-contents: read

- name: Install develop tools
  uses: fujimogn/develop-tools-action@61618529ddb05a6b36df8c64d0b298f95dec6f15 # v0.2.0
  with:
    token: ${{ steps.develop-tools-token.outputs.token }}
```

The GitHub App must be installed on `fujimogn/develop-meta` with Contents read permission. The caller supplies the App credentials; this action contains no credentials and does not print the installation token.

Commit `.develop-tools.json` at your repository root:

```json
{
  "version": "1.2.3",
  "sha256": {
    "x86_64-unknown-linux-gnu": "<64 lowercase hexadecimal characters>"
  }
}
```

Replace the example version and digest with the release version and its archive SHA256. The action reads this file from `GITHUB_WORKSPACE`, downloads `develop-tools-v<version>-linux-x86_64.tar.gz` and `SHA256SUMS` from the `v<version>` release, and verifies both the published checksum and the archive against the committed digest. A failed download is retried up to three attempts, five seconds apart. A missing asset or checksum mismatch fails the step. Only verified executable regular files are installed and added to `GITHUB_PATH` for subsequent steps.

The tool version is controlled by your committed manifest. The action version controls the installation procedure independently. The example pins the full commit SHA targeted by the `v0.2.0` tag. The published `v1.0.0` through `v1.0.2` tags and the working `v1` tag remain available at their existing commits.

## Development

Run `bash tests/run.sh` for offline fixture tests covering successful installation, a retried transient download failure, a missing release asset, archive SHA256 mismatch, and token-free logs on success and API failure. Run `bash -n scripts/install-tools.sh tests/run.sh` for shell syntax validation. Tests use a mock GitHub CLI and never call an external API. Temporary fixture directories are printed at the end for inspection; GitHub-hosted runners clean up their workspace after the job.

## License

[MIT](LICENSE).
