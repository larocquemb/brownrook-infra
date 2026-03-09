#!/usr/bin/env bash
set -euo pipefail

IDC_REPO="${IDC_REPO:-$HOME/Developer/brownrook/brownrook-idc}"
INFRA_REPO="${INFRA_REPO:-$HOME/Developer/brownrook/brownrook-infra}"
APP="brownrook-idc"

to_utc() {
    local ts="${1:-}"

    if [[ -z "$ts" || "$ts" == "unknown" || "$ts" == "null" ]]; then
        echo "unknown"
        return
    fi

    date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$(echo "$ts" | sed 's/Z/+0000/')" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || echo "$ts"
}

epoch() {
    local ts="$1"
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null || echo ""
}

delta() {
    local a="$1"
    local b="$2"

    ea=$(epoch "$a")
    eb=$(epoch "$b")

    if [[ -z "$ea" || -z "$eb" ]]; then
        echo "n/a"
        return
    fi

    echo "$((ea-eb))s"
}

echo
echo "=== IDC Deployment Timing (UTC) ==="
echo

APP_COMMIT=$(git -C "$IDC_REPO" rev-parse HEAD)
APP_TIME_RAW=$(git -C "$IDC_REPO" show -s --format='%cI' HEAD)
APP_TIME=$(to_utc "$APP_TIME_RAW")

REMOTE_APP_COMMIT=$(git -C "$IDC_REPO" ls-remote origin main | awk '{print $1}')

LOCAL_INFRA_COMMIT=$(git -C "$INFRA_REPO" rev-parse HEAD)
LOCAL_INFRA_TIME_RAW=$(git -C "$INFRA_REPO" show -s --format='%cI' HEAD)
LOCAL_INFRA_TIME=$(to_utc "$LOCAL_INFRA_TIME_RAW")

REMOTE_INFRA_COMMIT=$(git -C "$INFRA_REPO" ls-remote origin main | awk '{print $1}')
REMOTE_INFRA_TIME_RAW=$(git -C "$INFRA_REPO" show -s --format='%cI' "$REMOTE_INFRA_COMMIT")
REMOTE_INFRA_TIME=$(to_utc "$REMOTE_INFRA_TIME_RAW")

ARGO_JSON=$(kubectl get application "$APP" -n argocd -o json)

ARGO_REV=$(jq -r '.status.sync.revision' <<<"$ARGO_JSON")
ARGO_START=$(to_utc "$(jq -r '.status.operationState.startedAt' <<<"$ARGO_JSON")")
ARGO_FINISH=$(to_utc "$(jq -r '.status.operationState.finishedAt' <<<"$ARGO_JSON")")
ARGO_HEALTH=$(to_utc "$(jq -r '.status.health.lastTransitionTime' <<<"$ARGO_JSON")")

VERSION_JSON=$(curl -fsS https://idc.brownrook.com/version)

PUBLIC_COMMIT=$(jq -r '.commit' <<<"$VERSION_JSON")
PUBLIC_VERSION=$(jq -r '.version' <<<"$VERSION_JSON")
PUBLIC_BUILD=$(jq -r '.build' <<<"$VERSION_JSON")

echo "APP"
echo "  local commit:   $APP_COMMIT"
echo "  commit time:    $APP_TIME"
echo "  remote commit:  $REMOTE_APP_COMMIT"
echo

echo "INFRA"
echo "  local commit:   $LOCAL_INFRA_COMMIT"
echo "  local time:     $LOCAL_INFRA_TIME"
echo "  remote commit:  $REMOTE_INFRA_COMMIT"
echo "  remote time:    $REMOTE_INFRA_TIME"
echo

echo "ARGO"
echo "  sync revision:  $ARGO_REV"
echo "  started:        $ARGO_START"
echo "  finished:       $ARGO_FINISH"
echo "  healthy:        $ARGO_HEALTH"
echo

echo "PUBLIC"
echo "  version:        $PUBLIC_VERSION"
echo "  build:          $PUBLIC_BUILD"
echo "  commit:         $PUBLIC_COMMIT"
echo

echo "STATE"

[[ "$ARGO_REV" == "$REMOTE_INFRA_COMMIT" ]] \
  && echo "  ✔ Argo matches remote infra main" \
  || echo "  ⚠ Argo behind remote infra main"

[[ "$PUBLIC_COMMIT" == "$REMOTE_APP_COMMIT" ]] \
  && echo "  ✔ Public endpoint matches remote IDC main" \
  || echo "  ⚠ Public endpoint behind remote IDC main"

[[ "$PUBLIC_COMMIT" == "$APP_COMMIT" ]] \
  && echo "  ✔ Public endpoint matches local IDC HEAD" \
  || echo "  ℹ Public endpoint differs from local IDC HEAD"

echo
echo "TIMING"

echo "  infra push → argo start:  $(delta "$ARGO_START" "$REMOTE_INFRA_TIME")"
echo "  argo start → healthy:     $(delta "$ARGO_HEALTH" "$ARGO_START")"
echo "  app commit → healthy:     $(delta "$ARGO_HEALTH" "$APP_TIME")"
echo