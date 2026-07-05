#!/usr/bin/env bash
#
# Remove the `<ref>-bak` rollback images left by `yarn docker:release:pull`,
# then reclaim any now-dangling layers. Run once a fresh deploy is confirmed
# healthy — after this there's no one-command rollback to the previous image.
#
#   yarn docker:prune
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f .env ] && { set -a; . ./.env; set +a; }
API_IMAGE="${API_IMAGE:-{{image_repo}}:api}"
WEB_IMAGE="${WEB_IMAGE:-{{image_repo}}:web}"

for ref in "$API_IMAGE" "$WEB_IMAGE"; do
  if docker image inspect "${ref}-bak" >/dev/null 2>&1; then
    echo "==> Removing ${ref}-bak"
    docker rmi "${ref}-bak" >/dev/null || true
  else
    echo "==> No ${ref}-bak to remove"
  fi
done

echo "==> Reclaiming dangling layers"
docker image prune -f >/dev/null
echo "✅ Done."
