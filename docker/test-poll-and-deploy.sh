#!/bin/bash
# Mocked tests for docker/poll-and-deploy.sh — failure-origin classification.
#
# Verifies the task acceptance criteria:
#   AC1: GitHub-origin failures (API 5xx/429, network 000, download 403/410/5xx)
#        never post a Discord failure alert — stderr/logs only.
#   AC2: local failures (unzip/validation/rsync) still post ONE alert with the
#        reason, then the cooldown suppresses repeats.
#   AC3: after GitHub failures, a successful deploy posts the success message
#        and clears failure state.
#
# Run:  bash docker/test-poll-and-deploy.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/poll-and-deploy.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok:   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected [$2], got [$3])"; fi; }
assert_contains() { case "$3" in *"$2"*) ok "$1";; *) fail "$1 (expected to contain [$2], got [$3])";; esac; }

# Fresh isolated state per run. Export BEFORE sourcing so the script's top-level
# mkdir / file-path setup lands in temp dirs (it runs under `set -e`).
export STATE_DIR="$(mktemp -d)"
export SITE_DIR="$(mktemp -d)"
export WORK_DIR="$(mktemp -d)"
export GITHUB_OWNER="meany"
export GITHUB_REPO="log"
export GITHUB_TOKEN="test-token"
export DISCORD_WEBHOOK_URL="https://discord.example/webhook"
export API_RETRY_ATTEMPTS="1"     # single attempt, no sleeps -> deterministic
export API_RETRY_BASE_SLEEP="0"
export FAILURE_ALERT_COOLDOWN_SECONDS="3600"

# Source function definitions with the top-level while-loop stripped so it does
# not actually start polling.
source <(sed '/^while true; do$/,$d' "$SCRIPT") >/dev/null 2>&1
set +e  # tests control exit-code flow themselves

# --- notification capture (overrides notify_discord) ---
NOTIFY_LOG="$WORK_DIR/notify.log"
notify_discord() { printf '%s|%s\n' "$1" "$2" >> "$NOTIFY_LOG"; }
notify_count() { grep -c "^$1|" "$NOTIFY_LOG" 2>/dev/null; }
reset_notify() { : > "$NOTIFY_LOG"; rm -f "$STATE_DIR/last_failure_alert"; }

# ---------------------------------------------------------------------------
# AC1: GitHub-origin failures are silent on Discord (logs only).
# ---------------------------------------------------------------------------
echo "AC1: GitHub-origin failures never alert Discord"

# 1a. api_get classifies a GitHub API 5xx as origin=github.
MOCK_CURL_HTTP_CODE="503"
curl() {
  local outfile="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-o" ] && outfile="${args[$((i+1))]}"; done
  [ -n "$outfile" ] && printf '{"message":"API rate limit exceeded"}' > "$outfile"
  printf '%s' "$MOCK_CURL_HTTP_CODE"
}
clear_failure_reason; clear_failure_origin
api_get "https://api.github.com/repos/meany/log/actions/runs/1/artifacts" >/dev/null 2>&1
assert_eq "api_get returns 1 on 503" "1" "$?"
assert_eq "api_get sets reason 'GitHub API HTTP 503'" "GitHub API HTTP 503" "$(get_failure_reason)"
assert_eq "api_get sets origin 'github'" "github" "$(get_failure_origin)"

# 1b. Consecutive github-origin failures -> zero notify_discord failure calls.
reset_notify
set_failure_reason "GitHub API HTTP 503"
set_failure_origin "github"
handle_deploy_failure
handle_deploy_failure
handle_deploy_failure
assert_eq "github origin posts 0 failure alerts" "0" "$(notify_count failure)"
assert_eq "github origin posts 0 success alerts" "0" "$(notify_count success)"

# 1c. Artifact download 403 (GitHub infra/expiry) -> origin=github, silent.
api_get() { printf '{"artifacts":[{"name":"site","expired":false,"archive_download_url":"https://api.github.com/zip"}]}'; }
MOCK_CURL_HTTP_CODE="403"
clear_failure_reason; clear_failure_origin
deploy_run 123 "abc123" >/dev/null 2>&1
assert_eq "download 403 returns 1" "1" "$?"
assert_eq "download 403 origin 'github'" "github" "$(get_failure_origin)"
assert_eq "download 403 reason" "artifact download HTTP 403" "$(get_failure_reason)"

# 1d. Artifact download 401 (OUR token broken) -> origin=local (still alerts).
MOCK_CURL_HTTP_CODE="401"
clear_failure_reason; clear_failure_origin
deploy_run 124 "abc124" >/dev/null 2>&1
assert_eq "download 401 origin 'local'" "local" "$(get_failure_origin)"
assert_eq "download 401 reason" "artifact download HTTP 401" "$(get_failure_reason)"

# ---------------------------------------------------------------------------
# AC2: local failures still post ONE alert with reason, then cooldown.
# ---------------------------------------------------------------------------
echo "AC2: local failures alert once with reason, cooldown suppresses repeats"

# 2a. unzip failure -> origin=local.
MOCK_CURL_HTTP_CODE="200"
curl() {
  local outfile="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-o" ] && outfile="${args[$((i+1))]}"; done
  [ -n "$outfile" ] && printf 'not-a-zip' > "$outfile"
  printf '%s' "$MOCK_CURL_HTTP_CODE"
}
unzip() { return 1; }
clear_failure_reason; clear_failure_origin
deploy_run 125 "abc125" >/dev/null 2>&1
assert_eq "unzip failure origin 'local'" "local" "$(get_failure_origin)"
assert_eq "unzip failure reason" "artifact unzip failed" "$(get_failure_reason)"

# 2b. validation failure (missing index.html) -> origin=local.
unset -f unzip
VALID_TMP="$(mktemp -d)"
printf 'x' > "$VALID_TMP/other.html"
( cd "$VALID_TMP" && zip -q "$VALID_TMP/site.zip" other.html )
curl() {
  local outfile="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-o" ] && outfile="${args[$((i+1))]}"; done
  [ -n "$outfile" ] && cp "$VALID_TMP/site.zip" "$outfile"
  printf '%s' "$MOCK_CURL_HTTP_CODE"
}
clear_failure_reason; clear_failure_origin
deploy_run 126 "abc126" >/dev/null 2>&1
assert_eq "validation failure origin 'local'" "local" "$(get_failure_origin)"
assert_eq "validation failure reason" "artifact validation failed (missing index.html)" "$(get_failure_reason)"

# 2c. rsync failure -> origin=local.
GOOD_TMP="$(mktemp -d)"
printf '<html/>' > "$GOOD_TMP/index.html"
( cd "$GOOD_TMP" && zip -q "$GOOD_TMP/site.zip" index.html )
curl() {
  local outfile="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-o" ] && outfile="${args[$((i+1))]}"; done
  [ -n "$outfile" ] && cp "$GOOD_TMP/site.zip" "$outfile"
  printf '%s' "$MOCK_CURL_HTTP_CODE"
}
rsync() { return 1; }
clear_failure_reason; clear_failure_origin
deploy_run 127 "abc127" >/dev/null 2>&1
assert_eq "rsync failure origin 'local'" "local" "$(get_failure_origin)"
assert_eq "rsync failure reason" "site sync (rsync) failed" "$(get_failure_reason)"

# 2d. local failure alerts ONCE with reason, then cooldown suppresses.
reset_notify
set_failure_reason "site sync (rsync) failed"
set_failure_origin "local"
handle_deploy_failure
handle_deploy_failure
assert_eq "local failure posts exactly 1 alert" "1" "$(notify_count failure)"
assert_contains "alert carries reason text" "site sync (rsync) failed" "$(grep '^failure|' "$NOTIFY_LOG" | head -n1)"

# ---------------------------------------------------------------------------
# AC3: after GitHub failures, a successful deploy posts success + clears state.
# ---------------------------------------------------------------------------
echo "AC3: successful deploy after GitHub failures recovers cleanly"

unset -f rsync unzip 2>/dev/null   # restore real unzip/rsync for the happy path
# api_get returns a runs listing then an artifacts listing, keyed on the URL.
api_get() {
  case "$1" in
    */artifacts) printf '{"artifacts":[{"name":"site","expired":false,"archive_download_url":"https://api.github.com/zip"}]}' ;;
    *) printf '{"total_count":1,"workflow_runs":[{"id":128,"head_sha":"abc128"}]}' ;;
  esac
}
MOCK_CURL_HTTP_CODE="200"
curl() {
  local outfile="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-o" ] && outfile="${args[$((i+1))]}"; done
  [ -n "$outfile" ] && cp "$GOOD_TMP/site.zip" "$outfile"
  printf '%s' "$MOCK_CURL_HTTP_CODE"
}

# Simulate a prior GitHub-origin failure state.
set_failure_reason "GitHub API HTTP 429"
set_failure_origin "github"
reset_notify
deploy_latest >/dev/null 2>&1
assert_eq "deploy_latest succeeds" "0" "$?"
assert_eq "success message posted once" "1" "$(notify_count success)"
assert_eq "no failure alert posted" "0" "$(notify_count failure)"
assert_eq "failure reason cleared" "unknown" "$(get_failure_reason)"
if [ -f "$STATE_DIR/last_failure_origin" ]; then
  fail "failure origin file not cleared"
else
  ok "failure origin file cleared"
fi

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
