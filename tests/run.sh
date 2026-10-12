#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/develop-tools-action-tests.XXXXXXXX")
# Leave ownership and cleanup to the caller/runner; no recursive deletion.
trap 'echo "Test fixtures: $tmp"' EXIT
mkdir -p "$tmp/fixture" "$tmp/mock" "$tmp/workspace" "$tmp/runner"
printf '#!/bin/sh\necho fixture-tool\n' > "$tmp/fixture/develop-docs-check"
chmod +x "$tmp/fixture/develop-docs-check"
asset=develop-tools-v1.2.3-linux-x86_64.tar.gz
tar -czf "$tmp/fixture/$asset" -C "$tmp/fixture" develop-docs-check
sha=$(sha256sum "$tmp/fixture/$asset"); sha=${sha%% *}
printf '%s  %s\n' "$sha" "$asset" > "$tmp/fixture/SHA256SUMS"
cat > "$tmp/mock/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$GH_TOKEN" == "$TEST_TOKEN" ]]
[[ "${GH_DEBUG:-}" == '' && "$GH_HOST" == github.com ]]
[[ "$1" == api ]]
case "$2" in
  repos/fujimogn/develop-meta/releases/tags/v1.2.3)
    printf '{"assets":[{"id":11,"name":"develop-tools-v1.2.3-linux-x86_64.tar.gz"},{"id":12,"name":"SHA256SUMS"}]}' ;;
  repos/fujimogn/develop-meta/releases/assets/11)
    [[ "$3" == -H && "$4" == 'Accept: application/octet-stream' ]]
    cat "$FIXTURE/develop-tools-v1.2.3-linux-x86_64.tar.gz" ;;
  repos/fujimogn/develop-meta/releases/assets/12)
    cat "$FIXTURE/SHA256SUMS" ;;
  *) exit 1 ;;
esac
if [[ ${API_FAIL:-0} == 1 ]]; then
  echo "$GH_TOKEN" >&2
  exit 1
fi
MOCK
chmod +x "$tmp/mock/gh"
export TEST_TOKEN='fixture-secret-do-not-print' DEVELOP_TOOLS_TOKEN='fixture-secret-do-not-print'
export FIXTURE="$tmp/fixture" GITHUB_WORKSPACE="$tmp/workspace" RUNNER_TEMP="$tmp/runner" GITHUB_PATH="$tmp/path"
export PATH="$tmp/mock:$PATH" GH_DEBUG=api
manifest() { printf '{"version":"1.2.3","sha256":{"x86_64-unknown-linux-gnu":"%s"}}\n' "$1" > "$tmp/workspace/.develop-tools.json"; }
check_secret() { if grep -Fq -- "$TEST_TOKEN" "$tmp/log"; then echo 'FAIL: token leaked'; exit 1; fi; }
manifest "$sha"
bash -x "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1
check_secret
installed=$(cat "$GITHUB_PATH")
[[ $("$installed/develop-docs-check") == fixture-tool ]]
echo 'PASS: successful install and executable on PATH'
: > "$GITHUB_PATH"
# Make release metadata agree with the pin, but corrupt the actual archive.
printf 'corruption' >> "$tmp/fixture/$asset"
if bash "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1; then echo 'FAIL: accepted checksum mismatch'; exit 1; fi
grep -q -- 'Archive SHA256 mismatch' "$tmp/log"
[[ ! -s "$GITHUB_PATH" ]]
check_secret
echo 'PASS: SHA256 mismatch fails before PATH update'
if API_FAIL=1 bash -x "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1; then echo 'FAIL: API error succeeded'; exit 1; fi
check_secret
grep -q -- 'Release download failed' "$tmp/log"
[[ ! -s "$GITHUB_PATH" ]]
echo 'PASS: token absent from success and failure logs (including shell tracing)'
