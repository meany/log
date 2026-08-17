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
# Force a deploy on every container start, regardless of prior state.
rm -f "$LAST_RUN_FILE"
# Do not remove last_sha file to persist last deployed SHA


api_get() {
  url="$1"
  tmp_body="$WORK_DIR/api-body.json"

  http_code="$(curl -sSL -o "$tmp_body" -w "%{http_code}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "$url")"

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "GitHub API request failed: status=$http_code url=$url" >&2
    echo "Expected token permission: actions=read" >&2

    if [ "$DEBUG_API" = "true" ] && [ -s "$tmp_body" ]; then
      echo "API response body:" >&2
      cat "$tmp_body" >&2
    fi
    return 1
  fi

  cat "$tmp_body"
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

  if [ "$head_sha" = "$last_sha" ]; then
    if [ "$STARTUP_CHECK" = "true" ]; then
      echo "Container started successfully with SHA $head_sha"
      notify_discord success "Container started successfully with SHA \`${head_sha:0:7}\`"
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
  if ! curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ***" \
    -L "$download_url" \
    -o "$zip_path"; then
    echo "Artifact download failed for run_id=$run_id (URL may be expired or inaccessible)" >&2
    return 1
  fi

  if ! unzip -q "$zip_path" -d "$out_dir"; then
    echo "Artifact unzip failed for run_id=$run_id" >&2
    return 1
  fi

  # Guard against wiping SITE_DIR with an empty or malformed artifact.
  if [ ! -f "$out_dir/index.html" ]; then
    echo "Artifact content validation failed for run_id=$run_id (missing index.html)" >&2
    return 1
  fi

  # Sync new static output into mounted site directory.
  if ! rsync -a --delete "$out_dir/" "$SITE_DIR/"; then
    echo "Site sync failed for run_id=$run_id" >&2
    return 1
  fi

  echo "$run_id" > "$LAST_RUN_FILE"
  echo "$head_sha" > "$LAST_SHA_FILE"
  echo "[DEPLOY] Success. run_id=$run_id sha=$head_sha. Site updated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  notify_discord success "Deployed \`${run_id}\` (\`${head_sha:0:7}\`) at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

deploy_latest() {
  # Scan recent successful runs (newest first) and deploy the newest one whose
  # artifact is still downloadable. GitHub deletes artifacts after the retention
  # window (see build.yml), so the newest successful run may already be
  # undeployable; falling back to an older run with a live artifact keeps the
  # site current without failure alerts caused by expired artifacts.
  local page=1
  local total_count=""

  while [ "$page" -le 10 ]; do
    runs_url="$API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/workflows/$WORKFLOW_FILE/runs?branch=$BRANCH&status=success&per_page=30&page=$page"
    runs_json="$(api_get "$runs_url")" || return 1
    total_count="$(echo "$runs_json" | jq -r '.total_count // 0')"

    local rc=0
    while read -r run_id head_sha; do
      [ -z "$run_id" ] && continue
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

while true; do
  if [ "$POLLING_ENABLED" = "true" ]; then
    if ! deploy_latest; then
      echo "Deploy attempt failed; retrying in $POLL_INTERVAL_SECONDS seconds" >&2
      notify_discord failure "Deploy failed for \`$GITHUB_OWNER/$GITHUB_REPO\` at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
    STARTUP_CHECK="false"
  fi

  if [ "$RUN_ONCE" = "true" ]; then
    echo "RUN_ONCE=true set; exiting after one deploy check."
    exit 0
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
