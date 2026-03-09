#!/usr/bin/env bash
set -euo pipefail

IDC_REPO="${IDC_REPO:-$HOME/Developer/brownrook/brownrook-idc}"
INFRA_REPO="${INFRA_REPO:-$HOME/Developer/brownrook/brownrook-infra}"
APP="brownrook-idc"

to_utc() {
  local ts="${1:-}"
  python3 - "$ts" <<'PY'
import sys
from datetime import datetime, timezone

ts = sys.argv[1]
if not ts or ts in {"unknown", "null"}:
    print("unknown")
    raise SystemExit(0)

try:
    dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    print(dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
except Exception:
    print(ts)
PY
}

epoch_utc() {
  local ts="${1:-}"
  python3 - "$ts" <<'PY'
import sys
from datetime import datetime, timezone

ts = sys.argv[1]
if not ts or ts in {"unknown", "null"}:
    print("")
    raise SystemExit(0)

try:
    dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    print(int(dt.astimezone(timezone.utc).timestamp()))
except Exception:
    print("")
PY
}

delta() {
  local newer="$1"
  local older="$2"

  local en eo
  en="$(epoch_utc "$newer")"
  eo="$(epoch_utc "$older")"

  if [[ -z "$en" || -z "$eo" ]]; then
    echo "n/a"
    return
  fi

  echo "$((en - eo))s"
}

echo "=== IDC Deployment Timing (UTC) ==="
echo

git -C "$IDC_REPO" fetch origin --prune >/dev/null 2>&1
git -C "$INFRA_REPO" fetch origin --prune >/dev/null 2>&1

APP_COMMIT="$(git -C "$IDC_REPO" rev-parse HEAD)"
APP_TIME="$(to_utc "$(git -C "$IDC_REPO" show -s --format='%cI' HEAD)")"
REMOTE_APP_COMMIT="$(git -C "$IDC_REPO" rev-parse origin/main)"
REMOTE_APP_TIME="$(to_utc "$(git -C "$IDC_REPO" show -s --format='%cI' origin/main)")"

LOCAL_INFRA_COMMIT="$(git -C "$INFRA_REPO" rev-parse HEAD)"
LOCAL_INFRA_TIME="$(to_utc "$(git -C "$INFRA_REPO" show -s --format='%cI' HEAD)")"
REMOTE_INFRA_COMMIT="$(git -C "$INFRA_REPO" rev-parse origin/main)"
REMOTE_INFRA_TIME="$(to_utc "$(git -C "$INFRA_REPO" show -s --format='%cI' origin/main)")"

ARGO_JSON="$(kubectl get application "$APP" -n argocd -o json)"
ARGO_REV="$(jq -r '.status.sync.revision' <<<"$ARGO_JSON")"
ARGO_START="$(to_utc "$(jq -r '.status.operationState.startedAt // "unknown"' <<<"$ARGO_JSON")")"
ARGO_FINISH="$(to_utc "$(jq -r '.status.operationState.finishedAt // "unknown"' <<<"$ARGO_JSON")")"
ARGO_HEALTH="$(to_utc "$(jq -r '.status.health.lastTransitionTime // "unknown"' <<<"$ARGO_JSON")")"

VERSION_JSON="$(curl -fsS https://idc.brownrook.com/version)"
PUBLIC_COMMIT="$(jq -r '.commit' <<<"$VERSION_JSON")"
PUBLIC_VERSION="$(jq -r '.version' <<<"$VERSION_JSON")"
PUBLIC_BUILD="$(jq -r '.build' <<<"$VERSION_JSON")"

echo "APP"
echo "  local commit:   $APP_COMMIT"
echo "  local time:     $APP_TIME"
echo "  remote commit:  $REMOTE_APP_COMMIT"
echo "  remote time:    $REMOTE_APP_TIME"
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
if [[ "$ARGO_REV" == "$REMOTE_INFRA_COMMIT" ]]; then
  echo "  ✔ Argo matches remote infra main"
else
  echo "  ⚠ Argo does not match remote infra main"
fi

if [[ "$LOCAL_INFRA_COMMIT" == "$REMOTE_INFRA_COMMIT" ]]; then
  echo "  ✔ local infra matches remote infra main"
else
  echo "  ℹ local infra does not match remote infra main"
fi

if [[ "$PUBLIC_COMMIT" == "$REMOTE_APP_COMMIT" ]]; then
  echo "  ✔ Public endpoint matches remote IDC main"
else
  echo "  ⚠ Public endpoint behind remote IDC main"
fi

if [[ "$PUBLIC_COMMIT" == "$APP_COMMIT" ]]; then
  echo "  ✔ Public endpoint matches local IDC HEAD"
else
  echo "  ℹ Public endpoint does not match local IDC HEAD"
fi
echo

echo "TIMING"
echo "  app remote → infra remote: $(delta "$REMOTE_INFRA_TIME" "$REMOTE_APP_TIME")"
echo "  infra push → argo start:   $(delta "$ARGO_START" "$REMOTE_INFRA_TIME")"
echo "  argo start → healthy:      $(delta "$ARGO_HEALTH" "$ARGO_START")"
echo "  app remote → healthy:      $(delta "$ARGO_HEALTH" "$REMOTE_APP_TIME")"
echo