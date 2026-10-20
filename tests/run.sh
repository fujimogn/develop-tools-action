#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/develop-tools-action-tests.XXXXXXXX")
cleanup() {
  rm -f "$fixture/action/resolve" "$fixture/install.sh" "$fixture/github-path" "$fixture/failure.log"
  rm -f "$fixture/plan.sh" "$fixture/manifest.json" "$fixture/plan-output" "$fixture/plan.log"
  rmdir "$fixture/action" "$fixture/workspace" "$fixture/cache" "$fixture"
}
trap cleanup EXIT
mkdir -p "$fixture/action" "$fixture/workspace" "$fixture/cache"
awk '
  /^      run: \|$/ { reading = 1; next }
  reading && /^        / { sub(/^        /, ""); print; next }
  reading { exit }
' "$root/action.yml" > "$fixture/install.sh"
[[ -s "$fixture/install.sh" ]]
bash -n "$fixture/install.sh"
cat > "$fixture/action/resolve" <<'MOCK'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = bin-dir ] && [ "$2" = ci ] || exit 2
printf '%s\n' "$TEST_BIN_DIR"
MOCK
chmod +x "$fixture/action/resolve"
export GITHUB_WORKSPACE="$fixture/workspace" GITHUB_PATH="$fixture/github-path"
export DEVELOP_TOOLS_ACTION_PATH="$fixture/action" XDG_CACHE_HOME="$fixture/cache"
export TEST_BIN_DIR="$fixture/custom bin"
bash "$fixture/install.sh"
[[ $(cat "$GITHUB_PATH") == "$TEST_BIN_DIR" ]]
echo 'PASS: resolver bin-dir output is added to PATH'
: > "$GITHUB_PATH"
if DEVELOP_TOOLS_ACTION_PATH="$fixture/missing" bash "$fixture/install.sh" > "$fixture/failure.log" 2>&1; then
  echo 'FAIL: missing resolver succeeded' >&2
  exit 1
fi
[[ ! -s "$GITHUB_PATH" ]]
echo 'PASS: missing resolver fails before PATH update'

# The plan tests do not use the resolver cache; tool shims must not write into the fixture.
unset XDG_CACHE_HOME
workflow="$root/.github/workflows/platform-check.yml"
cases="$root/tests/fixtures/platform-declarations.json"
# plan step の run block を取り出す。reusable workflow は呼び元を checkout するので script は workflow に直接書く。
awk '
  /^      - name: Plan platforms$/ { step = 1; next }
  step && /^        run: \|$/ { reading = 1; next }
  reading && (/^          / || /^$/) { sub(/^          /, ""); print; next }
  reading { exit }
' "$workflow" > "$fixture/plan.sh"
[[ -s "$fixture/plan.sh" ]]
bash -n "$fixture/plan.sh"
count=$(jq '.cases | length' "$cases")
for ((i = 0; i < count; i++)); do
  name=$(jq -r ".cases[$i].name" "$cases")
  jq ".cases[$i].manifest" "$cases" > "$fixture/manifest.json"
  : > "$fixture/plan-output"
  if MANIFEST="$fixture/manifest.json" GITHUB_OUTPUT="$fixture/plan-output" bash "$fixture/plan.sh" > "$fixture/plan.log" 2>&1; then
    if [[ $(jq ".cases[$i].expect.error // false" "$cases") == true ]]; then
      echo "FAIL: $name was accepted" >&2
      exit 1
    fi
    include=$(sed -n 's/^include=//p' "$fixture/plan-output")
    expected=$(jq -c ".cases[$i].expect.platforms" "$cases")
    [[ $(jq -c '[.[].os]' <<< "$include") == "$expected" ]] || { echo "FAIL: $name matrix $include" >&2; exit 1; }
    jq -e 'all(.[]; .runner == {linux: "ubuntu-latest", macos: "macos-latest", windows: "windows-latest"}[.os])' <<< "$include" > /dev/null \
      || { echo "FAIL: $name runner $include" >&2; exit 1; }
    jq -e 'type == "object"' <<< "$(sed -n 's/^check=//p' "$fixture/plan-output")" > /dev/null
  elif [[ $(jq ".cases[$i].expect.error // false" "$cases") != true ]]; then
    cat "$fixture/plan.log" >&2
    echo "FAIL: $name was refused" >&2
    exit 1
  fi
done
echo "PASS: plan matches $count platform declarations"
# shellcheck disable=SC2016 # the workflow expression is matched literally
grep -Fqx '    name: platform (${{ matrix.os }})' "$workflow"
grep -Fqx '      fail-fast: false' "$workflow"
grep -Fqx '        shell: bash' "$workflow"
grep -Eq '^  group: platform-check-' "$workflow"
if grep -Fq 'github.workflow' "$workflow"; then
  echo 'FAIL: concurrency must not use github.workflow' >&2
  exit 1
fi
echo 'PASS: job name, fail-fast, shell and concurrency contract'
