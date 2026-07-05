# Boilerplate examples

Battle-tested patterns extracted from real projects (crk-mind-cache, crk-stocks,
crk-agent-gallery, ai-chat), made agnostic. These are **templates, not live code**:
copy them into a new project and replace the placeholders.

## Placeholders

| Placeholder | Meaning | Example |
|---|---|---|
| `{{project_name}}` | Human-readable name | `Mind Cache` |
| `{{project_name\|machine_name}}` | Snake-case prefix (containers, db, network, env defaults) | `mind_cache` |
| `{{project_name\|slug}}` | Kebab-case slug (image names, keys) | `mind-cache` |
| `{{port_band}}` | Two-digit dev port-band prefix from `~/GITCRK/PORTS.md` (see `ports.md`) | `55` → web 5510, api 5520 |
| `{{prod_port_web}}` / `{{prod_port_api}}` | Prod host ports (separate 10xxx band) | `10310` / `10320` |
| `{{domain}}` | Public production domain | `myapp.example.com` |
| `{{image_repo}}` | Docker registry repo | `dockerhubuser/my-app` |
| `{{boilerplate_repo_url}}` | This boilerplate's git URL | — |
| `{{components}}` | Feature description in the kickoff prompt | — |

## Contents

| File | What it is |
|---|---|
| `README-template.md` | Skeleton for the new project's README (brief → Quick start Local/Production → Release/Rollback/Reverse proxy → Stack → Layout → Ports) |
| `ports.md` | How to claim a port band from `~/GITCRK/PORTS.md` and record it |
| `docker/docker-compose.yml` | Dev stack: postgres + api + web + pgadmin(profile), bind-mounted source, deps installed at container start |
| `docker/docker-compose-prod.yml` | Prod stack: registry images, internal-only postgres, migrations on boot |
| `docker/api.Dockerfile` | Prod api image: multi-stage, webpack-bundled Nest + pruned deps + esbuild migrate runner |
| `docker/web.Dockerfile` | Prod web image: Next standalone output, `NEXT_PUBLIC_*` baked as build args |
| `../../docker/local.Dockerfile` | Dev image (in the boilerplate root): thin runtime shell, source bind-mounted |
| `env/.env.example` | Dev env template — mirrors every compose `${VAR:-default}` |
| `env/.env.prod.example` | Prod env template — minimal: required secrets + overrides |
| `release/RELEASE.md` | Release flow: build+push on a RAM host, pull+restart on the VPS, `-bak` rollback |
| `release/scripts/*.sh` | `docker-release.sh`, `docker-release-pull.sh`, `docker-prune.sh` |
| `reverse-proxy.md` | Single-origin path-routed proxy (Apache vhost + Caddy) with TLS |
| `auth/google-oauth.md` | Google login: env vars, Passport strategy, JWT cookie, graceful 503 when unconfigured |
| `database/drizzle.md` | Drizzle schema/migrations/seed layout and how migrations run in dev vs prod |
| `stacks.md` | Drop-in compose blocks: TimescaleDB, Elasticsearch, Redis, MinIO, MailHog, SearXNG, vLLM, filesystem storage |

## Non-negotiable conventions

1. **Ports**: claim a free 100-port band, wrap every host port in `${VAR:-default}`,
   update `~/GITCRK/PORTS.md` (sorted), declare the allocation in the README.
2. **Fully dockerized dev**: `docker compose up -d` must work with zero edits on a
   fresh clone (all env defaults baked into the compose file).
3. **Optional features degrade gracefully**: missing Google creds → 503 on the login
   route only; missing Elasticsearch → postgres fallback; missing mail provider →
   MailHog. The app never crashes because an optional integration is unconfigured.
4. **Prod = images from a registry**: never build on the VPS, never bind-mount source
   in prod, migrations run idempotently on api boot, postgres never published.
5. **Single origin in prod**: web at `/`, api at `/api`, one domain, first-party
   cookie, no CORS.
6. **Secrets**: only in `.env` (gitignored). `.env.example` carries placeholders.
