#!/bin/bash
set -euo pipefail

API_BASE="https://api.github.com"
STATE_DIR="${STATE_DIR:-/state}"
SITE_DIR="${SITE_DIR:-/site}"
WORK_DIR="${WORK_DIR:-/work}"
WORKFLOW_FILE="build.yml"
ARTIFACT_NAME="site"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-120}"
BRANCH="main"
RUN_ONCE="${RUN_ONCE:-false}"
DEBUG_API="${DEBUG_API:-false}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

# Failure-alert hardening: retry transient GitHub API errors with backoff, and
# rate-limit Discord failure notifications so one transient failure can never
# spam the channel. A failure is reported at most once per cooldown window.
API_RETRY_ATTEMPTS="${API_RETRY_ATTEMPTS:-3}"
API_RETRY_BASE_SLEEP="${API_RETRY_BASE_SLEEP:-10}"
FAILURE_ALERT_COOLDOWN_SECONDS="${FAILURE_ALERT_COOLDOWN_SECONDS:-3600}"
FAILURE_BACKOFF_SECONDS="${FAILURE_BACKOFF_SECONDS:-600}"

require_env() {
  local name="$1"
  local value
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required env var: $name" >&2
    exit 1
  fi
}

POLLING_ENABLED="true"
STARTUP_CHECK="true"

if [ -z "${GITHUB_OWNER:-}" ] || [ -z "${GITHUB_REPO:-}" ] || [ -z "${GITHUB_TOKEN:-}" ]; then
  POLLING_ENABLED="false"
  echo "GitHub env vars not set. Poll agent is idle (serving bundled /site content only)."
else
  echo "Poll agent started. Polling $GITHUB_OWNER/$GITHUB_REPO for new builds every $POLL_INTERVAL_SECONDS seconds."
fi

mkdir -p "$STATE_DIR" "$SITE_DIR" "$WORK_DIR"
LAST_RUN_FILE="$STATE_DIR/last_run_id"
LAST_SHA_FILE="$STATE_DIR/last_sha"
LAST_FAILURE_REASON_FILE="$STATE_DIR/last_failure_reason"
LAST_FAILURE_ALERT_FILE="$STATE_DIR/last_failure_alert"
LAST_FAILURE_ORIGIN_FILE="$STATE_DIR/last_failure_origin"
# Persist last_run_id and last_sha across restarts so the freshness check in
# deploy_run() can recognize commits that were already processed and skip them.

# Record the human-readable reason for the most recent failure so the Discord
# message can explain WHY the deploy failed (e.g. "GitHub API HTTP 429" vs
# "artifact download HTTP 401"). Stored in a file because functions that write
# the reason run inside $(...) subshells where shell variables don't propagate.
set_failure_reason() {
  printf '%s' "$1" > "$LAST_FAILURE_REASON_FILE"
}
clear_failure_reason() {
  rm -f "$LAST_FAILURE_REASON_FILE"
}
get_failure_reason() {
  if [ -f "$LAST_FAILURE_REASON_FILE" ]; then
    cat "$LAST_FAILURE_REASON_FILE"
  else
    echo "unknown"
  fi
}

# Classify each failure by ORIGIN so the alert policy can tell GitHub-side
# outages (API rate limits/errors, expired artifacts, network reachability)
# apart from failures on OUR side of the pipeline. GitHub-origin failures are
# logged to stderr only; Discord failure alerts are reserved for local failures
# (unzip, validation, rsync, and auth). Stored in a file alongside the reason
# for the same subshell-propagation reason.
set_failure_origin() {
  printf '%s' "$1" > "$LAST_FAILURE_ORIGIN_FILE"
}
clear_failure_origin() {
  rm -f "$LAST_FAILURE_ORIGIN_FILE"
}
get_failure_origin() {
  if [ -f "$LAST_FAILURE_ORIGIN_FILE" ]; then
    cat "$LAST_FAILURE_ORIGIN_FILE"
  else
    # Default to "local": if an origin was never recorded we must NOT silently
    # swallow a real failure - alert as if it were ours.
    echo "local"
  fi
}

# True (0) when a failure alert should be posted now; false (1) when suppressed
# by the cooldown window. Records the timestamp of the last alert in STATE_DIR so
# only the FIRST failure in a window notifies Discord.
should_alert_failure() {
  [ -z "$DISCORD_WEBHOOK_URL" ] && return 1
  local now last
  now="$(date +%s)"
  if [ -f "$LAST_FAILURE_ALERT_FILE" ]; then
    last="$(cat "$LAST_FAILURE_ALERT_FILE" 2>/dev/null || echo 0)"
    if [ "$((now - last))" -lt "$FAILURE_ALERT_COOLDOWN_SECONDS" ]; then
      return 1
    fi
  fi
  echo "$now" > "$LAST_FAILURE_ALERT_FILE"
  return 0
}

api_get() {
  url="$1"
  tmp_body="$WORK_DIR/api-body.json"
  local attempt=1
  local backoff="$API_RETRY_BASE_SLEEP"
  local http_code=""

  while [ "$attempt" -le "$API_RETRY_ATTEMPTS" ]; do
    # Guard with `|| true` so a network-level curl failure (exit != 0, code 000)
    # does not trip `set -e` and kill the whole script into a restart loop.
    http_code="$(curl -sSL -o "$tmp_body" -w "%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      "$url" || true)"

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
      cat "$tmp_body"
      return 0
    fi

    echo "GitHub API request failed: status=$http_code url=$url (attempt $attempt/$API_RETRY_ATTEMPTS)" >&2
    echo "Expected token permission: actions=read" >&2

    if [ "$DEBUG_API" = "true" ] && [ -s "$tmp_body" ]; then
      echo "API response body:" >&2
      cat "$tmp_body" >&2
    fi

    if [ "$attempt" -lt "$API_RETRY_ATTEMPTS" ]; then
      echo "Retrying in ${backoff}s..." >&2
      sleep "$backoff"
      backoff=$((backoff * 2))
    fi
    attempt=$((attempt + 1))
  done

  set_failure_reason "GitHub API HTTP $http_code"
  set_failure_origin "github"
  return 1
}

notify_discord() {
  local status="$1"
  local description="$2"
  [ -z "$DISCORD_WEBHOOK_URL" ] && return 0

  local color=3066993
  [ "$status" = "failure" ] && color=15158332

  local payload
  payload="$(jq -n --arg desc "$description" --argjson color "$color" \
    '{"embeds":[{"title":"meany-log-poll-and-deploy","description":$desc,"color":$color}]}')"

  curl -sSf -X POST "$DISCORD_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    > /dev/null 2>&1 || true
}

# Deploy a specific run if it is newer than what we are running.
# Returns:
#   0 - deployed, or already running this SHA/run (nothing to do)
#   1 - real failure (API error, download/validation/sync error)
#   2 - run is not deployable (artifact missing/expired) - try an older run
deploy_run() {
  local run_id="$1"
  local head_sha="$2"

  local last_run_id=""
  if [ -f "$LAST_RUN_FILE" ]; then
    last_run_id="$(cat "$LAST_RUN_FILE")"
  fi

  local last_sha=""
  if [ -f "$LAST_SHA_FILE" ]; then
    last_sha="$(cat "$LAST_SHA_FILE")"
  fi

  # Freshness check: skip (and stay silent) when this run's commit SHA has
  # already been processed. The comparison is keyed on SHA/run id — never on
  # timestamps or artifact names — so a re-poll of an unchanged repo is a no-op.
  if [ "$head_sha" = "$last_sha" ]; then
    if [ "$STARTUP_CHECK" = "true" ]; then
      echo "Container started successfully with SHA $head_sha"
    else
      echo "No changes detected. Current SHA $head_sha"
    fi
    return 0
  fi

  if [ "$run_id" = "$last_run_id" ]; then
    return 0
  fi

  artifacts_url="$API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id/artifacts"
  artifacts_json="$(api_get "$artifacts_url")" || return 1

  download_url="$(echo "$artifacts_json" | jq -r --arg name "$ARTIFACT_NAME" '.artifacts[] | select(.name == $name and (.expired | not)) | .archive_download_url' | head -n1)"

  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
    # Not a failure: GitHub expired/removed this run's artifact. Skip to an older run.
    echo "Artifact '$ARTIFACT_NAME' expired or missing for run_id=$run_id; skipping" >&2
    return 2
  fi

  tmp_dir="$WORK_DIR/run-$run_id"
  zip_path="$tmp_dir/site.zip"
  out_dir="$tmp_dir/out"

  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir" "$out_dir"

  echo "Downloading artifact run_id=$run_id sha=$head_sha"
  local dl_code
  dl_code="$(curl -sSL -o "$zip_path" -w "%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -L "$download_url" || true)"
  if [ "$dl_code" -lt 200 ] || [ "$dl_code" -ge 300 ]; then
    set_failure_reason "artifact download HTTP $dl_code"
    # Classify download failures by origin. HTTP 401 historically means OUR
    # token was broken (an auth failure on our side, not GitHub being down), so
    # it is treated as a local failure and still alerts. Every other non-2xx
    # from the GitHub blob/signed URL (403/410/5xx/000) is GitHub infra or an
    # expired artifact, so it is logged only.
    if [ "$dl_code" = "401" ]; then
      set_failure_origin "local"
    else
      set_failure_origin "github"
    fi
    echo "Artifact download failed for run_id=$run_id (HTTP $dl_code; URL may be expired or inaccessible)" >&2
    return 1
  fi

  if ! unzip -q "$zip_path" -d "$out_dir"; then
    set_failure_reason "artifact unzip failed"
    set_failure_origin "local"
    echo "Artifact unzip failed for run_id=$run_id" >&2
    return 1
  fi

  # Guard against wiping SITE_DIR with an empty or malformed artifact.
  if [ ! -f "$out_dir/index.html" ]; then
    set_failure_reason "artifact validation failed (missing index.html)"
    set_failure_origin "local"
    echo "Artifact content validation failed for run_id=$run_id (missing index.html)" >&2
    return 1
  fi

  # Sync new static output into mounted site directory.
  if ! rsync -a --delete "$out_dir/" "$SITE_DIR/"; then
    set_failure_reason "site sync (rsync) failed"
    set_failure_origin "local"
    echo "Site sync failed for run_id=$run_id" >&2
    return 1
  fi

  echo "[DEPLOY] Success. run_id=$run_id sha=$head_sha. Site updated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  notify_discord success "Deployed \`${run_id}\` (\`${head_sha:0:7}\`) at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Persist the last-processed run id and SHA only AFTER a successful
  # notification, so a notification that fails (or is suppressed) is retried on
  # the next poll instead of being silently marked as seen.
  echo "$run_id" > "$LAST_RUN_FILE"
  echo "$head_sha" > "$LAST_SHA_FILE"
}

deploy_latest() {
  # Scan recent successful runs (newest first) and deploy the newest one whose
  # artifact is still downloadable. GitHub deletes artifacts after the retention
  # window (see build.yml), so the newest successful run may already be
  # undeployable; falling back to an older run with a live artifact keeps the
  # site current without failure alerts caused by expired artifacts.
  clear_failure_reason
  clear_failure_origin
  local page=1
  local total_count=""

  while [ "$page" -le 10 ]; do
    runs_url="$API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/workflows/$WORKFLOW_FILE/runs?branch=$BRANCH&status=success&per_page=30&page=$page"
    runs_json="$(api_get "$runs_url")" || return 1
    total_count="$(echo "$runs_json" | jq -r '.total_count // 0')"

    local rc=0
    while read -r run_id head_sha; do
      [ -z "$run_id" ] && continue
      # Always capture deploy_run's exit code (reset rc first, then capture on
      # failure via `||`). The old `deploy_run ... || rc=$?` left rc stuck at its
      # previous value after a *successful* deploy, so a prior rc=2 (expired
      # artifact) made the loop keep walking into older, already-seen runs and
      # re-deploy them — the source of repeated "Deployed" messages.
      rc=0
      deploy_run "$run_id" "$head_sha" || rc=$?
      if [ "$rc" -eq 0 ]; then
        return 0
      fi
      if [ "$rc" -ne 2 ]; then
        return "$rc"
      fi
    done < <(echo "$runs_json" | jq -r '.workflow_runs[] | "\(.id) \(.head_sha)"')

    if [ "$((page * 30))" -ge "$total_count" ]; then
      break
    fi
    page=$((page + 1))
  done

  echo "No deployable artifact found in recent successful runs; leaving current site as-is." >&2
  return 0
}

handle_deploy_failure() {
  local reason origin
  reason="$(get_failure_reason)"
  origin="$(get_failure_origin)"
  echo "Deploy attempt failed: $reason (origin=$origin)" >&2
  if [ "$origin" = "github" ]; then
    # GitHub-origin failures (API status, network reachability, expired or
    # inaccessible artifacts) are logged to stderr ONLY. We never alert Discord
    # for these: a multi-hour GitHub incident must not page the channel.
    echo "GitHub-origin failure; logging only (no Discord alert)." >&2
    return 0
  fi
  if should_alert_failure; then
    notify_discord failure "Deploy failed for \`$GITHUB_OWNER/$GITHUB_REPO\`: $reason at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    echo "Failure alert suppressed (cooldown ${FAILURE_ALERT_COOLDOWN_SECONDS}s)." >&2
  fi
}

while true; do
  sleep_seconds="$POLL_INTERVAL_SECONDS"
  if [ "$POLLING_ENABLED" = "true" ]; then
    if ! deploy_latest; then
      handle_deploy_failure
      sleep_seconds="$FAILURE_BACKOFF_SECONDS"
    fi
    STARTUP_CHECK="false"
  fi

  if [ "$RUN_ONCE" = "true" ]; then
    echo "RUN_ONCE=true set; exiting after one deploy check."
    exit 0
  fi

  sleep "$sleep_seconds"
done
