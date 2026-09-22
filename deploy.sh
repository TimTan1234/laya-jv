#!/usr/bin/env bash
# Build and (re)deploy the laya-decision container.
#
# Usage:
#   ./deploy.sh                # CPU build, port 8100
#   USE_GPU=1 ./deploy.sh      # CUDA build + --gpus all
#   LAYA_PORT=9000 ./deploy.sh
#   LAYA_MODEL=typed-decisions ./deploy.sh
set -euo pipefail

PORT="${LAYA_PORT:-8100}"
MODEL="${LAYA_MODEL:-multilingual}"
NAME="laya-decision"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
HEALTH_TIMEOUT="${LAYA_HEALTH_TIMEOUT:-120}"

if [ "${USE_GPU:-0}" = "1" ]; then
  IMAGE=laya-decision:gpu
  BUILD_ARGS=(--build-arg CUDA=1 --build-arg LAYA_MODEL="$MODEL")
  RUN_ARGS=(--gpus all)
else
  IMAGE=laya-decision:latest
  BUILD_ARGS=(--build-arg LAYA_MODEL="$MODEL")
  RUN_ARGS=()
fi

echo "==> Building ${IMAGE} (LAYA_MODEL=${MODEL})"
docker build "${BUILD_ARGS[@]}" -t "$IMAGE" .

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
  "${RUN_ARGS[@]}" \
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
