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
asset=develop-tools-v1.2.3-linux-x86_64.tar.gz
[[ $# == 12 && "${*:1:9}" == "release download v1.2.3 --repo fujimogn/develop-meta --pattern $asset --pattern SHA256SUMS" ]]
[[ ${10} == --dir && -d ${11} && ${12} == --clobber ]]
echo call >> "$GH_CALLS"
if (( $(wc -l < "$GH_CALLS") <= ${GH_FAILING_CALLS:-0} )); then
  echo "$GH_TOKEN" >&2
  exit 1
fi
# Like gh, skip a pattern that matches no release asset.
[[ ${MISSING_ARCHIVE:-0} == 1 ]] || cp "$FIXTURE/$asset" "${11}/"
cp "$FIXTURE/SHA256SUMS" "${11}/"
MOCK
# Retries must not slow the tests down; record the delays instead.
printf '#!/bin/sh\necho "$@" >> "$SLEEP_CALLS"\n' > "$tmp/mock/sleep"
chmod +x "$tmp/mock/gh" "$tmp/mock/sleep"
export TEST_TOKEN='fixture-secret-do-not-print' DEVELOP_TOOLS_TOKEN='fixture-secret-do-not-print'
export FIXTURE="$tmp/fixture" GITHUB_WORKSPACE="$tmp/workspace" RUNNER_TEMP="$tmp/runner" GITHUB_PATH="$tmp/path"
export GH_CALLS="$tmp/gh-calls" SLEEP_CALLS="$tmp/sleep-calls" PATH="$tmp/mock:$PATH" GH_DEBUG=api
manifest() { printf '{"version":"1.2.3","sha256":{"x86_64-unknown-linux-gnu":"%s"}}\n' "$1" > "$tmp/workspace/.develop-tools.json"; }
check_secret() { if grep -Fq -- "$TEST_TOKEN" "$tmp/log"; then echo 'FAIL: token leaked'; exit 1; fi; }
reset_runner() { : > "$GITHUB_PATH"; : > "$GH_CALLS"; : > "$SLEEP_CALLS"; }
manifest "$sha"
reset_runner
bash -x "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1
check_secret
installed=$(cat "$GITHUB_PATH")
[[ $("$installed/develop-docs-check") == fixture-tool ]]
echo 'PASS: successful install and executable on PATH'
reset_runner
GH_FAILING_CALLS=1 bash -x "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1
check_secret
grep -q -- '::warning::Release download attempt 1 of' "$tmp/log"
installed=$(cat "$GITHUB_PATH")
[[ $("$installed/develop-docs-check") == fixture-tool ]]
echo 'PASS: transient download failure is retried'
reset_runner
if MISSING_ARCHIVE=1 bash "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1; then echo 'FAIL: accepted missing asset'; exit 1; fi
grep -q -- 'Required release asset is missing' "$tmp/log"
[[ ! -s "$GITHUB_PATH" ]]
echo 'PASS: missing release asset fails before PATH update'
reset_runner
# Make release metadata agree with the pin, but corrupt the actual archive.
printf 'corruption' >> "$tmp/fixture/$asset"
if bash "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1; then echo 'FAIL: accepted checksum mismatch'; exit 1; fi
grep -q -- 'Archive SHA256 mismatch' "$tmp/log"
[[ ! -s "$GITHUB_PATH" ]]
check_secret
echo 'PASS: SHA256 mismatch fails before PATH update'
reset_runner
if GH_FAILING_CALLS=99 bash -x "$root/scripts/install-tools.sh" > "$tmp/log" 2>&1; then echo 'FAIL: API error succeeded'; exit 1; fi
check_secret
grep -q -- '::error::Release download failed' "$tmp/log"
[[ $(wc -l < "$GH_CALLS") == 3 && $(cat "$SLEEP_CALLS") == $'5\n5' ]]
[[ ! -s "$GITHUB_PATH" ]]
echo 'PASS: token absent from success and failure logs (including shell tracing)'
