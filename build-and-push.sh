#!/usr/bin/env bash
# Build the laya-decision image and push it to Docker Hub so it can be
# pulled and run on the NAS (see deploy-remote.sh, run there over SSH).
#
# Prereq: `docker login` (once) with an account that can push to the
# target repo.
#
# Usage:
#   DOCKERHUB_USER=youruser ./build-and-push.sh
#   IMAGE_REPO=someuser/laya-decision ./build-and-push.sh   # override repo directly
#   TAG=v1.2.0 ./build-and-push.sh                          # also pushes :v1.2.0 alongside :latest
#   PLATFORM=linux/amd64,linux/arm64 ./build-and-push.sh    # multi-arch build
set -euo pipefail

MODEL="${LAYA_MODEL:-multilingual}"
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE_REPO="${IMAGE_REPO:-${DOCKERHUB_USER:?Set DOCKERHUB_USER=<your dockerhub username>, or IMAGE_REPO=<registry>/<repo> to target something other than Docker Hub}/laya-decision}"
TAG="${TAG:-}"

echo "==> Target image: ${IMAGE_REPO} (platform: ${PLATFORM})"

docker buildx inspect laya-builder >/dev/null 2>&1 || \
  docker buildx create --name laya-builder --use >/dev/null
docker buildx use laya-builder

TAG_NAMES=("latest")
[ -n "$TAG" ] && TAG_NAMES+=("$TAG")

TAG_ARGS=()
for t in "${TAG_NAMES[@]}"; do
  TAG_ARGS+=(-t "${IMAGE_REPO}:${t}")
done

echo "==> Building and pushing ${IMAGE_REPO} (LAYA_MODEL=${MODEL})"
docker buildx build \
  --platform "$PLATFORM" \
  --build-arg LAYA_MODEL="$MODEL" \
  "${TAG_ARGS[@]}" \
  --push \
  .

echo "==> Pushed:"
for t in "${TAG_NAMES[@]}"; do
  echo "   ${IMAGE_REPO}:${t}"
done
echo
echo "On the NAS, run deploy-remote.sh with IMAGE_REPO=${IMAGE_REPO}${TAG:+ TAG=${TAG}} to pull and start it."
