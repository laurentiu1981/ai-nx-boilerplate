#!/usr/bin/env bash
#
# Build the api + web release images and push them to the registry.
# Run on a host WITH RAM (the tsc/Next builds are memory-heavy) — never the VPS.
#
#   yarn docker:release               # tag = git short SHA (or a timestamp)
#   yarn docker:release v1.4.2        # explicit tag
#   IMAGE_REPO=ghcr.io/me/app yarn docker:release
#
# Pushes a pinned tag (api-<TAG>, web-<TAG>) AND moves the floating :api / :web
# tags. On the VPS: `yarn docker:release:pull` → `yarn prod:start`. Run
# `docker login <registry>` once first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Pick up IMAGE_REPO and the NEXT_PUBLIC_* build values if a local .env has them
# (runtime secrets like JWT_SECRET are NOT needed to build).
[ -f .env ] && { set -a; . ./.env; set +a; }

REPO="${IMAGE_REPO:-{{image_repo}}}"
TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d-%H%M%S)}"
API_IMAGE="$REPO:api-$TAG"
WEB_IMAGE="$REPO:web-$TAG"

# NEXT_PUBLIC_* are inlined into the web bundle at build time → bake the prod origin.
NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:-https://{{domain}}}"

echo "==> Building $API_IMAGE"
docker build -f docker/api.Dockerfile -t "$API_IMAGE" .

echo "==> Building $WEB_IMAGE"
docker build -f docker/web.Dockerfile \
  --build-arg NEXT_PUBLIC_API_URL="$NEXT_PUBLIC_API_URL" \
  -t "$WEB_IMAGE" .

echo "==> Pushing pinned tags"
docker push "$API_IMAGE"
docker push "$WEB_IMAGE"

echo "==> Updating floating tags ($REPO:api, $REPO:web)"
docker tag "$API_IMAGE" "$REPO:api" && docker push "$REPO:api"
docker tag "$WEB_IMAGE" "$REPO:web" && docker push "$REPO:web"

cat <<EOF

✅ Pushed release '$TAG'.
   floating: $REPO:api   $REPO:web
   pinned:   $API_IMAGE   $WEB_IMAGE

Next, on the VPS:  yarn docker:release:pull && yarn prod:start
                   yarn docker:prune          # drop the :*-bak backups once healthy
To pin/rollback, set these in the VPS .env (default: the floating tags above):
   API_IMAGE=$API_IMAGE
   WEB_IMAGE=$WEB_IMAGE
EOF
