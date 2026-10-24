#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/develop-tools-action-tests.XXXXXXXX")
cleanup() {
  rm -f "$fixture/action/resolve" "$fixture/install.sh" "$fixture/github-path" "$fixture/failure.log"
  rm -f "$fixture/plan.sh" "$fixture/manifest.json" "$fixture/plan-output" "$fixture/plan.log"
  rm -f "$fixture/workspaces.sh" "$fixture/step-output" "$fixture/step-env" "$fixture/each-workspace"
  rm -f "$fixture/old-python/python3"
  rmdir "$fixture/old-python" 2>/dev/null || true
  rm -f "$fixture/visited" "$fixture/bun.sh" "$fixture/bun-output" "$fixture/bun.log"
  rm -f "$fixture/workspace/.config/develop-tools.json" "$fixture/workspace/.develop-tools.json"
  rmdir "$fixture/workspace/.config" 2>/dev/null || true
  rmdir "$fixture/workspace/packages/cli" "$fixture/workspace/packages" "$fixture/workspace/tools" 2>/dev/null || true
  rmdir -- "$fixture/workspace/-n" "$fixture/workspace/-" 2>/dev/null || true
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
    check=$(sed -n 's/^check=//p' "$fixture/plan-output")
    jq -e 'type == "object"' <<< "$check" > /dev/null
    if [[ $(jq ".cases[$i].expect | has(\"check\")" "$cases") == true ]]; then
      expected=$(jq -cS ".cases[$i].expect.check" "$cases")
      [[ $(jq -cS . <<< "$check") == "$expected" ]] || { echo "FAIL: $name check $check" >&2; exit 1; }
    fi
  elif [[ $(jq ".cases[$i].expect.error // false" "$cases") != true ]]; then
    cat "$fixture/plan.log" >&2
    echo "FAIL: $name was refused" >&2
    exit 1
  fi
done
echo "PASS: plan matches $count platform declarations"

# Default manifest discovery: new-only, legacy-only, and both.
valid_manifest='{"platforms":["linux"],"release":{"preflightWorkflow":"release-platform-preflight.yml"}}'
mkdir -p "$fixture/workspace/.config"

# 1. New location only (.config/develop-tools.json)
printf '%s\n' "$valid_manifest" > "$fixture/workspace/.config/develop-tools.json"
rm -f "$fixture/workspace/.develop-tools.json"
: > "$fixture/plan-output"
if (cd "$fixture/workspace" && GITHUB_OUTPUT="$fixture/plan-output" bash "$fixture/plan.sh" > "$fixture/plan.log" 2>&1); then
  include=$(sed -n 's/^include=//p' "$fixture/plan-output")
  [[ $(jq -c '[.[].os]' <<< "$include") == '["linux"]' ]] || { echo "FAIL: default lookup new-only matrix $include" >&2; exit 1; }
else
  cat "$fixture/plan.log" >&2
  echo "FAIL: default lookup new-only failed" >&2
  exit 1
fi
echo 'PASS: default lookup accepts .config/develop-tools.json only'

# 2. Legacy location only (.develop-tools.json)
rm -f "$fixture/workspace/.config/develop-tools.json"
printf '%s\n' "$valid_manifest" > "$fixture/workspace/.develop-tools.json"
: > "$fixture/plan-output"
if (cd "$fixture/workspace" && GITHUB_OUTPUT="$fixture/plan-output" bash "$fixture/plan.sh" > "$fixture/plan.log" 2>&1); then
  include=$(sed -n 's/^include=//p' "$fixture/plan-output")
  [[ $(jq -c '[.[].os]' <<< "$include") == '["linux"]' ]] || { echo "FAIL: default lookup legacy-only matrix $include" >&2; exit 1; }
else
  cat "$fixture/plan.log" >&2
  echo "FAIL: default lookup legacy-only failed" >&2
  exit 1
fi
echo 'PASS: default lookup accepts .develop-tools.json only'

# 3. Both locations exist
printf '%s\n' "$valid_manifest" > "$fixture/workspace/.config/develop-tools.json"
printf '%s\n' "$valid_manifest" > "$fixture/workspace/.develop-tools.json"
: > "$fixture/plan-output"
if (cd "$fixture/workspace" && GITHUB_OUTPUT="$fixture/plan-output" bash "$fixture/plan.sh" > "$fixture/plan.log" 2>&1); then
  echo "FAIL: default lookup with both manifests unexpectedly passed" >&2
  exit 1
fi
grep -Fq '.config/develop-tools.json' "$fixture/plan.log" || { echo "FAIL: missing .config path in error: $(cat "$fixture/plan.log")" >&2; exit 1; }
grep -Fq '.develop-tools.json' "$fixture/plan.log" || { echo "FAIL: missing .develop-tools path in error: $(cat "$fixture/plan.log")" >&2; exit 1; }
echo 'PASS: default lookup rejects both manifests naming both paths'

rm -f "$fixture/workspace/.config/develop-tools.json" "$fixture/workspace/.develop-tools.json"
rmdir "$fixture/workspace/.config" 2>/dev/null || true
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
# Every Cargo step runs in each declared workspace, and the ignored tests run only when declared.
if grep -Eq 'working-directory: \$\{\{ env\.CARGO_WORKSPACE \}\}' "$workflow"; then
  echo 'FAIL: a Cargo step runs in one workspace only' >&2
  exit 1
fi
grep -Fqx '        if: fromJSON(needs.plan.outputs.check).runIgnored != null' "$workflow"
# shellcheck disable=SC2016 # the shell variable is matched literally
grep -Fq -- '--run-ignored only --no-tests=pass -E "$RUN_IGNORED"' "$workflow"
echo 'PASS: workspace list and ignored-test contract'

# Run the Cargo workspaces step itself: the list must survive the multiline file format and the
# helper must run a command in every workspace in order, stopping at the first failure.
awk '
  /^      - name: Cargo workspaces$/ { step = 1; next }
  step && /^        run: \|$/ { reading = 1; next }
  reading && (/^          / || /^$/) { sub(/^          /, ""); print; next }
  reading { exit }
' "$workflow" > "$fixture/workspaces.sh"
[[ -s "$fixture/workspaces.sh" ]]
mkdir -p "$fixture/workspace/tools" "$fixture/workspace/packages/cli"
: > "$fixture/step-output"
: > "$fixture/step-env"
(cd "$fixture/workspace" && CHECK='{"cargoWorkspaces":["tools","packages/cli"]}' RUNNER_TEMP="$fixture" \
  GITHUB_OUTPUT="$fixture/step-output" GITHUB_ENV="$fixture/step-env" bash -e "$fixture/workspaces.sh")
# Read a multiline value the way the runner does: from "<name><<<delimiter>" to the delimiter line.
multiline() {
  awk -v name="$1" '
    !reading && index($0, name "<<") == 1 { delimiter = substr($0, length(name) + 3); reading = 1; next }
    reading && $0 == delimiter { found = 1; exit }
    reading { print }
    END { if (!found) exit 1 }
  ' "$2"
}
[[ $(multiline list "$fixture/step-output") == $'tools\npackages/cli' ]] || { echo 'FAIL: workspace list output' >&2; exit 1; }
[[ $(multiline CARGO_WORKSPACES "$fixture/step-env") == $'tools\npackages/cli' ]] || { echo 'FAIL: workspace list env' >&2; exit 1; }
[[ $(sed -n 's/^EACH_WORKSPACE=//p' "$fixture/step-env") == "$fixture/each-workspace" ]]
# shellcheck disable=SC2016 # the helper expands the variable
(cd "$fixture/workspace" && CARGO_WORKSPACES=$'tools\npackages/cli' "$fixture/each-workspace" \
  bash -c 'basename "$PWD" >> "$0"' "$fixture/visited")
[[ $(cat "$fixture/visited") == $'tools\ncli' ]] || { echo 'FAIL: helper did not visit every workspace' >&2; exit 1; }
: > "$fixture/visited"
# shellcheck disable=SC2016 # the helper expands the variable
if (cd "$fixture/workspace" && CARGO_WORKSPACES=$'tools\npackages/cli' "$fixture/each-workspace" \
  bash -c 'basename "$PWD" >> "$0"; false' "$fixture/visited"); then
  echo 'FAIL: helper hid a failing workspace' >&2
  exit 1
fi
[[ $(cat "$fixture/visited") == tools ]] || { echo 'FAIL: helper went on after a failure' >&2; exit 1; }
# A workspace the plan accepts may start with '-': cd must not read it as an option or OLDPWD.
mkdir -p -- "$fixture/workspace/-n" "$fixture/workspace/-"
: > "$fixture/visited"
# shellcheck disable=SC2016 # the helper expands the variable
(cd "$fixture/workspace" && CARGO_WORKSPACES=$'-n\n-' "$fixture/each-workspace" \
  bash -c 'basename -- "$PWD" >> "$0"' "$fixture/visited") || true
[[ $(cat "$fixture/visited") == $'-n\n-' ]] || { echo 'FAIL: helper did not enter a workspace starting with -' >&2; exit 1; }
echo 'PASS: workspace list step and each-workspace helper'

# Bun version step: same resolver as generated CI. Prefer mise, fall back only when the file is absent.
awk '
  /^      - name: Resolve Bun version$/ { step = 1; next }
  step && /^        run: \|$/ { reading = 1; next }
  reading && (/^          / || /^$/) { sub(/^          /, ""); print; next }
  reading { exit }
' "$workflow" > "$fixture/bun.sh"
[[ -s "$fixture/bun.sh" ]]
bash -n "$fixture/bun.sh"
grep -Fqx '          open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8").write("version=%s\n" % next(iter(declared.values())))' "$workflow"
grep -Fqx '          bun-version: ${{ steps.develop-bun-version.outputs.version }}' "$workflow"
if grep -Fq 'bun-version-file:' "$workflow"; then
  echo 'FAIL: platform-check still pins bun-version-file' >&2
  exit 1
fi
# Prefer the system interpreter. A mise shim reads .config/mise.toml before Python starts.
bun_workspace=$(mktemp -d "$fixture/bun.XXXXXXXX")
expect_version() {
  local name=$1 expected=$2
  : > "$fixture/bun-output"
  if ! (cd "$bun_workspace" && PATH="$bun_python_path" GITHUB_OUTPUT="$fixture/bun-output" bash "$fixture/bun.sh") > "$fixture/bun.log" 2>&1; then
    cat "$fixture/bun.log" >&2
    echo "FAIL: $name" >&2
    exit 1
  fi
  [[ $(cat "$fixture/bun-output") == "version=$expected" ]] || {
    echo "FAIL: $name output $(cat "$fixture/bun-output")" >&2
    exit 1
  }
}
expect_fail() {
  local name=$1 needle=$2
  : > "$fixture/bun-output"
  if (cd "$bun_workspace" && PATH="$bun_python_path" GITHUB_OUTPUT="$fixture/bun-output" bash "$fixture/bun.sh") > "$fixture/bun.log" 2>&1; then
    echo "FAIL: $name succeeded" >&2
    exit 1
  fi
  [[ ! -s "$fixture/bun-output" ]] || { echo "FAIL: $name wrote a version" >&2; exit 1; }
  grep -Fq "$needle" "$fixture/bun.log" || { echo "FAIL: $name log $(cat "$fixture/bun.log")" >&2; exit 1; }
}
# Simulate Python before 3.11 even on hosts where tomllib is installed.
mkdir -p "$fixture/old-python"
export TEST_REAL_PYTHON=/usr/bin/python3
cat > "$fixture/old-python/python3" <<'MOCK'
#!/bin/sh
exec "$TEST_REAL_PYTHON" -c 'import sys; sys.modules["tomllib"] = None; exec(compile(sys.stdin.read(), "<stdin>", "exec"))'
MOCK
chmod +x "$fixture/old-python/python3"
mkdir -p "$bun_workspace/.config"
for interpreter in system without-tomllib; do
  bun_python_path="/usr/bin:/bin:${PATH}"
  if [[ $interpreter == without-tomllib ]]; then
    bun_python_path="$fixture/old-python:$bun_python_path"
  fi
  count=$(jq '.bunCases | length' "$cases")
  for ((i = 0; i < count; i++)); do
    name="$interpreter: $(jq -r ".bunCases[$i].name" "$cases")"
    rm -f "$bun_workspace/.config/mise.toml" "$bun_workspace/.tool-versions"
    if jq -e ".bunCases[$i] | has(\"mise\")" "$cases" >/dev/null; then
      jq -jr ".bunCases[$i].mise" "$cases" > "$bun_workspace/.config/mise.toml"
    fi
    if jq -e ".bunCases[$i] | has(\"legacy\")" "$cases" >/dev/null; then
      jq -jr ".bunCases[$i].legacy" "$cases" > "$bun_workspace/.tool-versions"
    fi
    if jq -e ".bunCases[$i] | has(\"error\")" "$cases" >/dev/null; then
      expect_fail "$name" "$(jq -r ".bunCases[$i].error" "$cases")"
    else
      expect_version "$name" "$(jq -r ".bunCases[$i].version" "$cases")"
    fi
  done
done
rm -f "$bun_workspace/.config/mise.toml" "$bun_workspace/.tool-versions"
rmdir "$bun_workspace/.config" "$bun_workspace"
echo 'PASS: bun version resolver with system Python and without tomllib'
