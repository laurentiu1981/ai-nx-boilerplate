#!/usr/bin/env bash
#
# Build the api + web release images and push them to the registry.
# Run on a host WITH RAM (the tsc/Next builds are memory-heavy) — never the VPS.
#
#   yarn docker:release               # tag = git short SHA (or a timestamp)
#   yarn docker:release v1.4.2        # explicit tag
#   IMAGE_REPO=ghcr.io/me/app yarn docker:release
#
# All projects share ONE private repo ({{docker_repository}}); the project and
# component are encoded in the tag ({{tag_pattern}} = {{project_name|slug}}-<service>):
#   {{docker_repository}}:{{project_name|slug}}-api          (floating)
#   {{docker_repository}}:{{project_name|slug}}-api-<TAG>    (pinned, for rollback)
#   {{docker_repository}}:{{project_name|slug}}-web          (floating)
#   {{docker_repository}}:{{project_name|slug}}-web-<TAG>    (pinned, for rollback)
# (Single-image projects use one {{project_name|slug}}-all tag instead — see RELEASE.md.)
# On the VPS: `yarn docker:release:pull` → `yarn prod:start`. Run
# `docker login <registry>` once first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Do NOT source .env here: on a dev machine it holds the DEV values
# (NEXT_PUBLIC_API_URL=http://localhost:{{port_band}}20/api), and NEXT_PUBLIC_* get
# BAKED into the web bundle — a release built with them would ship pointing at
# localhost. Only explicit environment variables override the prod defaults:
#   NEXT_PUBLIC_API_URL=https://other.host/api yarn docker:release
REPO="${IMAGE_REPO:-{{docker_repository}}}"
NAME="{{project_name|slug}}"
TAG="${1:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d-%H%M%S)}"
API_IMAGE="$REPO:$NAME-api-$TAG"
WEB_IMAGE="$REPO:$NAME-web-$TAG"

# NEXT_PUBLIC_* are inlined into the web bundle at build time → bake the prod origin.
NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:-https://{{domain}}/api}"
case "$NEXT_PUBLIC_API_URL" in
  *localhost*|*127.0.0.1*)
    echo "✋ Refusing to bake '$NEXT_PUBLIC_API_URL' into a release image." >&2
    echo "   Unset NEXT_PUBLIC_API_URL or point it at the public origin." >&2
    exit 1
    ;;
esac

echo "==> Building $API_IMAGE"
docker build -f docker/api.Dockerfile -t "$API_IMAGE" .

echo "==> Building $WEB_IMAGE"
docker build -f docker/web.Dockerfile \
  --build-arg NEXT_PUBLIC_API_URL="$NEXT_PUBLIC_API_URL" \
  -t "$WEB_IMAGE" .

echo "==> Pushing pinned tags"
docker push "$API_IMAGE"
docker push "$WEB_IMAGE"

echo "==> Updating floating tags ($REPO:$NAME-api, $REPO:$NAME-web)"
docker tag "$API_IMAGE" "$REPO:$NAME-api" && docker push "$REPO:$NAME-api"
docker tag "$WEB_IMAGE" "$REPO:$NAME-web" && docker push "$REPO:$NAME-web"

cat <<EOF

✅ Pushed release '$TAG'.
   floating: $REPO:$NAME-api   $REPO:$NAME-web
   pinned:   $API_IMAGE   $WEB_IMAGE

Next, on the VPS:  yarn docker:release:pull && yarn prod:start
                   yarn docker:prune          # drop the :*-bak backups once healthy
To pin/rollback, set these in the VPS .env (default: the floating tags above):
   API_IMAGE=$API_IMAGE
   WEB_IMAGE=$WEB_IMAGE
EOF
