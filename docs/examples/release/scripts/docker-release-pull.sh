#!/usr/bin/env bash
#
# Pull the latest api + web images on the VPS, keeping the current ones as a
# rollback backup. For each image ref it tags the currently-pulled image
# `<ref>-bak` BEFORE pulling, so the previous version survives the pull.
#
#   yarn docker:release:pull
#
# Then start the stack with `yarn prod:start`. Once it's healthy, drop the
# backups with `yarn docker:prune`. To roll back, retag `<ref>-bak` → `<ref>`
# and `yarn prod:start` again.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f .env ] && { set -a; . ./.env; set +a; }
# Match docker-compose-prod.yml's image defaults exactly.
API_IMAGE="${API_IMAGE:-{{docker_repository}}:{{project_name|slug}}-api}"
WEB_IMAGE="${WEB_IMAGE:-{{docker_repository}}:{{project_name|slug}}-web}"

for ref in "$API_IMAGE" "$WEB_IMAGE"; do
  if docker image inspect "$ref" >/dev/null 2>&1; then
    echo "==> Backing up $ref → ${ref}-bak"
    docker tag "$ref" "${ref}-bak"
  else
    echo "==> No existing $ref to back up (first deploy?)"
  fi
done

echo "==> Pulling latest images"
docker compose -f docker-compose-prod.yml pull api web

echo
echo "✅ Pulled. Next: yarn prod:start   (then yarn docker:prune once healthy)"
