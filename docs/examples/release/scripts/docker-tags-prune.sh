#!/usr/bin/env bash
#
# Delete old pinned release tags ({{project_name|slug}}-<svc>-<sha>) from
# Docker Hub, keeping the newest N per component. The floating tags are never
# touched, and neither are OTHER projects' tags in the shared repo — only tags
# matching this project's exact `<name>-<svc>-` prefixes are considered.
#
#   yarn docker:tags:prune            # dry run — shows what would be deleted
#   yarn docker:tags:prune --yes      # actually delete
#   KEEP=3 yarn docker:tags:prune --yes   # keep more than the latest one
#
# COMPONENTS defaults to "api web"; single-image projects set COMPONENTS=all.
#
# Auth: DOCKERHUB_USER (default: repo owner) + DOCKERHUB_TOKEN (a Docker Hub
# access token or password), via env or .env; falls back to the `docker login`
# credentials. Deleting a tag on Docker Hub removes just the tag; unreferenced
# layers are garbage-collected by Hub.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[ -f .env ] && { set -a; . ./.env; set +a; }

REPO="${DOCKERHUB_REPO:-{{docker_repository}}}"
NAME="{{project_name|slug}}"
COMPONENTS="${COMPONENTS:-api web}"
KEEP="${KEEP:-1}"
USER="${DOCKERHUB_USER:-${REPO%%/*}}"
TOKEN="${DOCKERHUB_TOKEN:-}"
HUB="https://hub.docker.com/v2"

# No DOCKERHUB_TOKEN? Reuse the `docker login` credentials: from the
# credential helper (Docker Desktop → OS keychain) or the plain config auth.
if [ -z "$TOKEN" ]; then
  CONF="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
  if [ -f "$CONF" ]; then
    HELPER=$(jq -r '.credsStore // empty' "$CONF")
    if [ -n "$HELPER" ] && command -v "docker-credential-${HELPER}" >/dev/null 2>&1; then
      CREDS=$(echo "https://index.docker.io/v1/" | "docker-credential-${HELPER}" get 2>/dev/null || true)
      if [ -n "$CREDS" ]; then
        HUSER=$(echo "$CREDS" | jq -r '.Username // empty')
        TOKEN=$(echo "$CREDS" | jq -r '.Secret // empty')
      fi
    else
      AUTH=$(jq -r '.auths["https://index.docker.io/v1/"].auth // empty' "$CONF")
      if [ -n "$AUTH" ]; then
        DECODED=$(echo "$AUTH" | base64 -d)
        HUSER="${DECODED%%:*}"
        TOKEN="${DECODED#*:}"
      fi
    fi
    if [ -n "${HUSER:-}" ] && [ -n "$TOKEN" ]; then
      USER="$HUSER"
      echo "==> Using docker login credentials for ${USER}"
    fi
  fi
fi

if [ -z "$TOKEN" ]; then
  read -r -s -p "Docker Hub token/password for ${USER}: " TOKEN; echo
fi

echo "==> Logging in to Docker Hub as ${USER}"
JWT=$(curl -fsS -H 'Content-Type: application/json' \
  -d "{\"username\": \"${USER}\", \"password\": \"${TOKEN}\"}" \
  "${HUB}/users/login" | jq -r .token)
[ -n "$JWT" ] && [ "$JWT" != "null" ] || { echo "Login failed" >&2; exit 1; }

for SVC in $COMPONENTS; do
  PREFIX="${NAME}-${SVC}-"
  echo "==> Listing ${REPO} tags matching ${PREFIX}*"
  TAGS_JSON="[]"
  URL="${HUB}/repositories/${REPO}/tags?page_size=100&name=${PREFIX}"
  while [ -n "$URL" ] && [ "$URL" != "null" ]; do
    PAGE=$(curl -fsS -H "Authorization: Bearer ${JWT}" "$URL")
    TAGS_JSON=$(jq -s 'add' <(echo "$TAGS_JSON") <(echo "$PAGE" | jq '[.results[] | {name, last_updated}]'))
    URL=$(echo "$PAGE" | jq -r .next)
  done

  # Hub's name filter is a substring match — enforce the real prefix, newest first.
  DOOMED=$(echo "$TAGS_JSON" | jq -r --arg p "$PREFIX" --argjson keep "$KEEP" \
    '[.[] | select(.name | startswith($p))] | sort_by(.last_updated) | reverse | .[$keep:][].name')

  # Local images with the same prefix (the build host accumulates one per release).
  LOCAL_DOOMED=""
  if command -v docker >/dev/null 2>&1; then
    LOCAL_DOOMED=$(docker images --format '{{.CreatedAt}}\t{{.Repository}}:{{.Tag}}' "$REPO" \
      | awk -F'\t' -v ref="${REPO}:${PREFIX}" 'index($2, ref) == 1 { print }' \
      | sort -r | awk -F'\t' -v keep="$KEEP" 'NR > keep { print $2 }')
  fi

  TOTAL=$(echo "$TAGS_JSON" | jq --arg p "$PREFIX" '[.[] | select(.name | startswith($p))] | length')
  if [ -z "$DOOMED" ] && [ -z "$LOCAL_DOOMED" ]; then
    echo "✅ ${SVC}: ${TOTAL} pinned tag(s) on Hub; nothing beyond the newest ${KEEP} to delete."
    continue
  fi

  echo "==> ${SVC}: ${TOTAL} pinned tag(s) on Hub; keeping newest ${KEEP}."
  [ -n "$DOOMED" ] && { echo "==> Hub tags to delete:"; echo "$DOOMED" | sed 's/^/    /'; }
  [ -n "$LOCAL_DOOMED" ] && { echo "==> Local images to untag:"; echo "$LOCAL_DOOMED" | sed 's/^/    /'; }

  if [ "${1:-}" != "--yes" ]; then
    echo "Dry run — re-run with --yes to delete."
    continue
  fi

  if [ -n "$LOCAL_DOOMED" ]; then
    while IFS= read -r REF; do
      echo "==> Untagging local ${REF}"
      docker rmi "$REF" >/dev/null || true
    done <<< "$LOCAL_DOOMED"
    echo "==> Reclaiming dangling layers"
    docker image prune -f >/dev/null
  fi

  [ -n "$DOOMED" ] || continue
  while IFS= read -r TAG; do
    echo "==> Deleting ${REPO}:${TAG}"
    curl -fsS -X DELETE -H "Authorization: Bearer ${JWT}" \
      "${HUB}/repositories/${REPO}/tags/${TAG}/" >/dev/null
  done <<< "$DOOMED"
done
echo "✅ Done."
