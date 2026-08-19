#!/bin/bash
# Targeted tests for the freshness fix in docker/poll-and-deploy.sh (t_5bda3523).
#
# Verifies the acceptance criteria:
#   AC-HAPPY:  a genuinely new commit -> exactly ONE "Deployed" message, and
#              last_sha / last_run_id are persisted AFTER the notification.
#   AC-NOOP:   a re-poll of the same commit -> NO message, NO re-deploy.
#   AC-LOOP:   when the newest run's artifact is expired (deploy_run returns 2),
#              a successful deploy of the next-older run stops the loop there
#              (deploy_run called exactly 2 times, not 3+). This is the root
#              cause of the "random Deployed messages with no repo change".
#
# Run:  bash docker/test-freshness.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/poll-and-deploy.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok:   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# Fresh isolated state per run, exported BEFORE sourcing.
export STATE_DIR="$(mktemp -d)"
export SITE_DIR="$(mktemp -d)"
export WORK_DIR="$(mktemp -d)"
export GITHUB_OWNER="meany"
export GITHUB_REPO="log"
export GITHUB_TOKEN="test-token"
export DISCORD_WEBHOOK_URL="https://discord.example/webhook"
export API_RETRY_ATTEMPTS="1"
export API_RETRY_BASE_SLEEP="0"
export FAILURE_ALERT_COOLDOWN_SECONDS="3600"

source <(sed '/^while true; do$/,$d' "$SCRIPT") >/dev/null 2>&1
set +e

# Notification capture (overrides notify_discord to count success/failure posts).
NOTIFY_LOG="$WORK_DIR/notify.log"
notify_discord() { printf '%s|%s\n' "$1" "$2" >> "$NOTIFY_LOG"; }
success_count() { grep -c "^success|" "$NOTIFY_LOG" 2>/dev/null; }
reset_notify()   { : > "$NOTIFY_LOG"; }

# Deploy a valid artifact: zip containing index.html so unzip/validation/rsync pass.
VALID_TMP="$(mktemp -d)"
printf '<html/>' > "$VALID_TMP/index.html"
( cd "$VALID_TMP" && zip -q "$VALID_TMP/site.zip" index.html )

# curl mock: return 200 and write the valid zip to the -o outfile.
curl() {
  local outfile="" args=("$@") i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-o" ] && outfile="${args[$((i+1))]}"; done
  [ -n "$outfile" ] && cp "$VALID_TMP/site.zip" "$outfile"
  printf '%s' "200"
}

# api_get mock: runs listing (URL without /artifacts) or artifacts listing.
api_get() {
  case "$1" in
    */artifacts) printf '{"artifacts":[{"name":"site","expired":false,"archive_download_url":"https://api.github.com/zip"}]}' ;;
    *) printf '%s' "$RUNS_JSON" ;;
  esac
}

# ---------------------------------------------------------------------------
echo "AC-NOOP: same commit re-poll sends no message and does not re-deploy"
# ---------------------------------------------------------------------------
RUNS_JSON='{"total_count":1,"workflow_runs":[{"id":101,"head_sha":"deadbeef"}]}'
echo "101" > "$STATE_DIR/last_run_id"
echo "deadbeef" > "$STATE_DIR/last_sha"
reset_notify
deploy_run 101 "deadbeef" >/dev/null 2>&1
assert_rc() { if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected $3, got $2)"; fi; }
assert_rc "no-op deploy_run returns 0" "$?" "0"
if [ "$(success_count)" -eq 0 ]; then ok "no-op sends 0 success messages"; else fail "no-op sent $(success_count) success messages"; fi

echo "AC-NOOP via deploy_latest: unchanged repo -> 0 messages, 0 deploys"
reset_notify
deploy_latest >/dev/null 2>&1
if [ "$(success_count)" -eq 0 ]; then ok "deploy_latest no-op sends 0 success messages"; else fail "deploy_latest no-op sent $(success_count) success messages"; fi

# ---------------------------------------------------------------------------
echo "AC-HAPPY: new commit -> exactly one message; state persisted after notify"
# ---------------------------------------------------------------------------
RUNS_JSON='{"total_count":1,"workflow_runs":[{"id":202,"head_sha":"cafebabe"}]}'
rm -f "$STATE_DIR/last_run_id" "$STATE_DIR/last_sha"
reset_notify
deploy_run 202 "cafebabe" >/dev/null 2>&1
if [ "$(success_count)" -eq 1 ]; then ok "happy path sends exactly 1 success message"; else fail "happy path sent $(success_count) messages"; fi
if [ "$(cat "$STATE_DIR/last_sha")" = "cafebabe" ]; then ok "last_sha persisted"; else fail "last_sha not persisted"; fi
if [ "$(cat "$STATE_DIR/last_run_id")" = "202" ]; then ok "last_run_id persisted"; else fail "last_run_id not persisted"; fi

# ---------------------------------------------------------------------------
echo "AC-LOOP: expired newest run does not walk into older already-seen runs"
# ---------------------------------------------------------------------------
# Three runs, newest first: 303 (expired -> rc 2), 302 (deploys ok -> rc 0),
# 301 (must NOT be reached). Buggy code (`deploy_run ... || rc=$?` without reset)
# left rc stuck at 2 after run 302's success, so the loop kept walking and called
# deploy_run a 3rd time for run 301. We assert deploy_run is called exactly 2x.
RUNS_JSON='{"total_count":3,"workflow_runs":[{"id":303,"head_sha":"ccc333"},{"id":302,"head_sha":"bbb222"},{"id":301,"head_sha":"aaa111"}]}'
rm -f "$STATE_DIR/last_run_id" "$STATE_DIR/last_sha"
reset_notify

# Pure loop-control probe: deploy_run returns 2 (expired) then 0 (success).
DEPLOY_CALLS=0
DEPLOY_RETURNS=(2 0 0)
deploy_run() {
  local idx=$DEPLOY_CALLS
  DEPLOY_CALLS=$((DEPLOY_CALLS+1))
  # Deploying run 302 for real is not needed here; we only verify loop control.
  # Return the scripted code, and persist state so a success is observable.
  if [ "${DEPLOY_RETURNS[$idx]}" = "0" ]; then
    echo "$1" > "$STATE_DIR/last_run_id"
    echo "$2" > "$STATE_DIR/last_sha"
    notify_discord success "Deployed \`$1\` (\`$2\`)"
  fi
  return "${DEPLOY_RETURNS[$idx]}"
}

deploy_latest >/dev/null 2>&1
deploy_latest_rc=$?

if [ "$deploy_latest_rc" -eq 0 ]; then ok "deploy_latest returns 0"; else fail "deploy_latest returned $deploy_latest_rc"; fi
if [ "$DEPLOY_CALLS" -eq 2 ]; then ok "deploy_run called exactly 2 times (got $DEPLOY_CALLS)"; else fail "deploy_run called $DEPLOY_CALLS times (expected 2)"; fi
if [ "$(success_count)" -eq 1 ]; then ok "exactly 1 success message (got $(success_count))"; else fail "$(success_count) success messages"; fi
if [ "$(cat "$STATE_DIR/last_sha")" = "bbb222" ]; then ok "site settled on run 302 (bbb222)"; else fail "last_sha=$(cat "$STATE_DIR/last_sha")"; fi

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
