#!/usr/bin/env bash
set +x
set -euo pipefail

fail() { echo "::error::$1" >&2; exit 1; }
[[ -n ${DEVELOP_TOOLS_TOKEN:-} ]] || fail 'The token input is required.'
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail 'Only Linux x86_64 runners are supported.'
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
download_attempts=3
download_retry_seconds=5
manifest="$GITHUB_WORKSPACE/.develop-tools.json"
# Never print the manifest or API response: both are external input.
version=$(jq -er '.version | strings | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$manifest" 2>/dev/null) || fail 'Invalid pinned version.'
expected=$(jq -er '.sha256["x86_64-unknown-linux-gnu"] | strings | select(test("^[0-9a-f]{64}$"))' "$manifest" 2>/dev/null) || fail 'Invalid pinned SHA256.'
asset="develop-tools-v${version}-linux-x86_64.tar.gz"
install_dir=$(mktemp -d "$RUNNER_TEMP/develop-tools.XXXXXXXX")
# On failure this directory is never added to PATH. The runner owns its cleanup.
# One gh process looks up the release and fetches both assets concurrently.
# Its output can carry API details, so none of it reaches the log. --clobber
# lets a retry overwrite an asset left by a failed attempt.
download() {
  GH_TOKEN="$DEVELOP_TOOLS_TOKEN" GH_DEBUG='' GH_HOST=github.com gh release download "v${version}" \
    --repo fujimogn/develop-meta --pattern "$asset" --pattern SHA256SUMS --dir "$install_dir" --clobber > /dev/null 2>&1
}
attempt=1
until download; do
  (( attempt < download_attempts )) || fail 'Release download failed.'
  echo "::warning::Release download attempt $attempt of $download_attempts failed; retrying." >&2
  sleep "$download_retry_seconds"
  attempt=$(( attempt + 1 ))
done
# gh exits 0 when only some of the patterns match a release asset.
[[ -f "$install_dir/$asset" && -f "$install_dir/SHA256SUMS" ]] || fail 'Required release asset is missing.'
release_sha=$(awk -v name="$asset" '$2 == name || $2 == "*" name {count++; digest=$1} END {if(count == 1) print digest; else exit 1}' "$install_dir/SHA256SUMS") || fail 'Invalid release checksum list.'
[[ "$release_sha" == "$expected" ]] || fail 'Release checksum differs from the pinned SHA256.'
actual=$(sha256sum "$install_dir/$asset")
[[ ${actual%% *} == "$expected" ]] || fail 'Archive SHA256 mismatch.'
# The release format is a flat set of executable regular files. Reject links,
# paths and duplicates before writing anything, even for a checksum-pinned file.
python3 - "$install_dir/$asset" "$install_dir/bin" <<'PY'
import os
import re
import sys
import tarfile

try:
    with tarfile.open(sys.argv[1], 'r:gz') as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if not members or len(names) != len(set(names)) or any(
            not member.isfile() or not re.fullmatch(r'[a-z0-9][a-z0-9-]*', member.name)
            or not member.mode & 0o111 for member in members
        ):
            raise ValueError('invalid archive')
        os.mkdir(sys.argv[2])
        for member in members:
            with archive.extractfile(member) as source, open(os.path.join(sys.argv[2], member.name), 'xb') as dest:
                dest.write(source.read())
            os.chmod(os.path.join(sys.argv[2], member.name), 0o755)
except Exception:
    print('::error::Invalid tool archive.', file=sys.stderr)
    sys.exit(1)
PY
printf '%s\n' "$install_dir/bin" >> "$GITHUB_PATH"
echo 'Installed checksum-verified develop tools.'
