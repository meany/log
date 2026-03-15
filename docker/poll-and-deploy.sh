#!/bin/bash
set -eu

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

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "Missing required env var: $name" >&2
    exit 1
  fi
}

polling_enabled="true"

if [ -z "${GITHUB_OWNER:-}" ] || [ -z "${GITHUB_REPO:-}" ] || [ -z "${GITHUB_TOKEN:-}" ]; then
  polling_enabled="false"
  echo "GitHub env vars not set. Poll agent is idle (serving bundled /site content only)."
else
  echo "Poll agent started. Polling $GITHUB_OWNER/$GITHUB_REPO for new builds every $POLL_INTERVAL_SECONDS seconds."
fi

mkdir -p "$STATE_DIR" "$SITE_DIR" "$WORK_DIR"
LAST_RUN_FILE="$STATE_DIR/last_run_id"

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

deploy_latest() {
  runs_url="$API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/workflows/$WORKFLOW_FILE/runs?branch=$BRANCH&status=success&per_page=1"
  run_json="$(api_get "$runs_url")"

  run_id="$(echo "$run_json" | jq -r '.workflow_runs[0].id // empty')"
  head_sha="$(echo "$run_json" | jq -r '.workflow_runs[0].head_sha // empty')"

  if [ -z "$run_id" ]; then
    echo "No successful runs found for workflow=$WORKFLOW_FILE branch=$BRANCH"
    return 0
  fi

  last_run_id=""
  if [ -f "$LAST_RUN_FILE" ]; then
    last_run_id="$(cat "$LAST_RUN_FILE")"
  fi

  if [ "$run_id" = "$last_run_id" ]; then
    echo "No new build artifact. run_id=$run_id"
    return 0
  fi

  artifacts_url="$API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id/artifacts"
  artifacts_json="$(api_get "$artifacts_url")"

  download_url="$(echo "$artifacts_json" | jq -r --arg name "$ARTIFACT_NAME" '.artifacts[] | select(.name == $name) | .archive_download_url' | head -n1)"

  if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
    echo "Artifact '$ARTIFACT_NAME' not found for run_id=$run_id"
    return 1
  fi

  tmp_dir="$WORK_DIR/run-$run_id"
  zip_path="$tmp_dir/site.zip"
  out_dir="$tmp_dir/out"

  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir" "$out_dir"

  echo "Downloading artifact run_id=$run_id sha=$head_sha"
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -L "$download_url" \
    -o "$zip_path"

  unzip -q "$zip_path" -d "$out_dir"

  # Sync new static output into mounted site directory.
  rsync -a --delete "$out_dir/" "$SITE_DIR/"

  echo "$run_id" > "$LAST_RUN_FILE"
  echo "[DEPLOY] Success. run_id=$run_id sha=$head_sha. Site updated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

while true; do
  if [ "$polling_enabled" = "true" ]; then
    if ! deploy_latest; then
      echo "Deploy attempt failed; retrying in $POLL_INTERVAL_SECONDS seconds" >&2
    fi
  fi

  if [ "$RUN_ONCE" = "true" ]; then
    echo "RUN_ONCE=true set; exiting after one deploy check."
    exit 0
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
