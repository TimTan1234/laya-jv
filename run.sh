#!/usr/bin/env bash
# Plain `docker run` launcher for the laya decision engine (Luna edition).
#
# Usage:
#   ./run.sh                # CPU build, port 8100
#   USE_GPU=1 ./run.sh      # CUDA build + --gpus all (needs NVIDIA driver w/ WSL support)
#   LAYA_PORT=9000 ./run.sh
set -euo pipefail

PORT="${LAYA_PORT:-8100}"
MODEL="${LAYA_MODEL:-multilingual}"

if [ "${USE_GPU:-0}" = "1" ]; then
  IMAGE=laya-decision:gpu
  docker image inspect "$IMAGE" >/dev/null 2>&1 || \
    docker build --build-arg CUDA=1 --build-arg LAYA_MODEL="$MODEL" -t "$IMAGE" .
  exec docker run -d \
    --name laya-decision \
    --restart unless-stopped \
    --gpus all \
    -p "${PORT}:8100" \
    -e LAYA_MODEL="$MODEL" \
    "$IMAGE"
else
  IMAGE=laya-decision:latest
  docker image inspect "$IMAGE" >/dev/null 2>&1 || \
    docker build --build-arg LAYA_MODEL="$MODEL" -t "$IMAGE" .
  exec docker run -d \
    --name laya-decision \
    --restart unless-stopped \
    -p "${PORT}:8100" \
    -e LAYA_MODEL="$MODEL" \
    "$IMAGE"
fi
