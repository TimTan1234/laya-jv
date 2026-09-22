#!/usr/bin/env bash
# Pull the laya-decision image from the registry and (re)deploy it.
# Run this ON THE NAS (e.g. over SSH), after build-and-push.sh has
# published a new image from the dev machine. No repo source needed here.
#
# Usage:
#   IMAGE_REPO=youruser/laya-decision ./deploy-remote.sh
#   IMAGE_REPO=youruser/laya-decision TAG=v1.2.0 ./deploy-remote.sh
#   LAYA_PORT=9000 IMAGE_REPO=youruser/laya-decision ./deploy-remote.sh
set -euo pipefail

IMAGE_REPO="${IMAGE_REPO:?Set IMAGE_REPO=<registry>/<repo>, e.g. youruser/laya-decision}"
TAG="${TAG:-latest}"
IMAGE="${IMAGE_REPO}:${TAG}"
PORT="${LAYA_PORT:-8100}"
MODEL="${LAYA_MODEL:-multilingual}"
NAME="laya-decision"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
HEALTH_TIMEOUT="${LAYA_HEALTH_TIMEOUT:-120}"

echo "==> Pulling ${IMAGE}"
docker pull "$IMAGE"

if docker inspect "$NAME" >/dev/null 2>&1; then
  echo "==> Removing existing ${NAME} container"
  docker rm -f "$NAME" >/dev/null
fi

echo "==> Starting ${NAME} on port ${PORT}"
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p "${PORT}:8100" \
  -e LAYA_MODEL="$MODEL" \
  "$IMAGE" >/dev/null

echo "==> Waiting for ${HEALTH_URL} (timeout ${HEALTH_TIMEOUT}s)"
elapsed=0
until curl -fsS -m 3 "$HEALTH_URL" >/tmp/laya-health.$$ 2>/dev/null; do
  if [ "$elapsed" -ge "$HEALTH_TIMEOUT" ]; then
    echo "==> FAILED: ${NAME} did not become healthy within ${HEALTH_TIMEOUT}s" >&2
    echo "---- last logs ----" >&2
    docker logs --tail 50 "$NAME" >&2
    rm -f /tmp/laya-health.$$
    exit 1
  fi
  sleep 3
  elapsed=$((elapsed + 3))
done

echo "==> Healthy:"
cat /tmp/laya-health.$$
echo
rm -f /tmp/laya-health.$$
echo "==> Deployed ${NAME} (${IMAGE}) on port ${PORT}"
