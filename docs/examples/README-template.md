# {{project_name|slug}}

<!-- ============================================================================
TEMPLATE for a new project's README.md, mirroring crk-mind-cache's structure.
The sections below (Quick start → Ports) should look like this in every project;
add further sections (Browser extension, CLI, jobs, …) as the project's structure
demands. One-line brief description first, then Quick start immediately — a fresh
clone must be runnable from the first screen of the README.
============================================================================= -->

{{project_name}} — one/two sentences: what it does, the app shape (Nx monorepo with
a Next.js web app + NestJS API), the backing stores (Postgres, …). End with
"Everything runs in Docker."

## Quick start

### Local

1. `cp .env.example .env` — defaults match `docker-compose.yml`.
2. Update `.env` as you see fit — `GOOGLE_*` for sign-in, other optional keys.
3. `docker compose up -d`
4. Open <http://localhost:{{port_band}}10>

### Production — {{domain}}

#### Release

**On local / CI** (`docker login <registry>` once first):

1. `yarn docker:release` — build + push the `api` & `web` images (tag = git short SHA).

**On the VPS:**

2. `yarn docker:release:pull` — back up the running images as `:*-bak`, then pull the new ones.
3. `yarn prod:start` — recreate the containers (api migrates on boot).
4. `yarn docker:prune` — remove the `:*-bak` backups once it's healthy.

#### First deploy (VPS)

1. If the project uses shared VPS services (shared Elasticsearch etc.), start the
   `crk-vps-shared` stack first (it provides the `crk_vps_shared` network):
   ```bash
   cd <path-to>/crk-vps-shared && docker compose up -d
   ```
2. `git clone <repo> {{project_name|slug}} && cd {{project_name|slug}}`
3. `cp .env.prod.example .env` — set `JWT_SECRET`, `POSTGRES_PASSWORD`, `IMAGE_REPO`
   (+ `GOOGLE_*` and other optional keys); `docker login <registry>` if private.
4. `yarn docker:release:pull && yarn prod:start` (after a `yarn docker:release` on local/CI).
5. Point the reverse proxy at the host (below), then open <https://{{domain}}>.

#### Rollback

Before `yarn docker:prune` the previous images are still tagged `:*-bak` — retag and restart:

```bash
docker tag {{docker_repository}}:{{project_name|slug}}-api-bak {{docker_repository}}:{{project_name|slug}}-api
docker tag {{docker_repository}}:{{project_name|slug}}-web-bak {{docker_repository}}:{{project_name|slug}}-web
yarn prod:start
```

Old pinned tags in the shared registry: `yarn docker:tags:prune` (dry run) /
`--yes` (delete; keeps the newest per component, other projects' tags untouched).

#### Reverse proxy (Apache vhost)

One domain, routed by path (`/api` + `/graphql` → `:{{prod_port_api}}`, everything
else → `:{{prod_port_web}}`) — no CORS, first-party cookie.
`a2enmod proxy proxy_http ssl headers`:

```apache
<VirtualHost *:443>
    ServerName {{domain}}

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/{{domain}}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/{{domain}}/privkey.pem

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"

    # Most-specific first (first match wins). API + GraphQL -> api, rest -> web.
    ProxyPass        /api      http://127.0.0.1:{{prod_port_api}}/api
    ProxyPassReverse /api      http://127.0.0.1:{{prod_port_api}}/api
    ProxyPass        /graphql  http://127.0.0.1:{{prod_port_api}}/graphql
    ProxyPassReverse /graphql  http://127.0.0.1:{{prod_port_api}}/graphql
    ProxyPass        /         http://127.0.0.1:{{prod_port_web}}/
    ProxyPassReverse /         http://127.0.0.1:{{prod_port_web}}/
</VirtualHost>

# Redirect http -> https
<VirtualHost *:80>
    ServerName {{domain}}
    Redirect permanent / https://{{domain}}/
</VirtualHost>
```

Set the Google OAuth **authorized redirect URI** to
`https://{{domain}}/api/auth/google/callback` (matches `GOOGLE_CALLBACK_URL`).

#### Notes

- Two compiled images (`api` — NestJS bundled to JS; `web` — Next.js standalone) + an
  internal Postgres, behind a reverse proxy. Build/push from a host with RAM (*not*
  the VPS), pull/restart on the VPS.
- <!-- shared services note if used, e.g.: Elasticsearch is the shared instance from
  the crk-vps-shared stack (optional; falls back to Postgres). -->
- Build-host CPU arch must match the VPS (x86_64), or build with
  `docker buildx --platform linux/amd64`.

## Stack

| Layer    | Tech |
|----------|------|
| Monorepo | Nx (yarn) |
| Web      | Next.js (App Router) + [`@overdoser/react-toolkit`](https://www.npmjs.com/package/@overdoser/react-toolkit) |
| API      | NestJS (GraphQL, Passport Google/JWT) |
| DB       | PostgreSQL + Drizzle ORM / drizzle-kit migrations |
<!-- add rows for the project's extras: Search (Elasticsearch), Cache (Redis), Storage (MinIO), … -->

## Layout

- `apps/web` — Next.js web app (UI).
- `apps/api` — NestJS API (`/graphql`, REST under `/api`).
- `libs/db` — Drizzle schema + migrations.
- `libs/shared` — types/helpers shared across apps.
- `playground/` — untracked scratch area (contents gitignored).
<!-- add the project's other apps/libs -->

## Ports (host side — see `~/GITCRK/PORTS.md`)

| Service       | Dev (`docker-compose.yml`) | Prod (`docker-compose-prod.yml`) |
|---------------|----------------------------|----------------------------------|
| web           | {{port_band}}10            | {{prod_port_web}}                |
| api           | {{port_band}}20            | {{prod_port_api}}                |
| postgres      | {{port_band}}30            | internal only                    |
<!-- add rows for extras (elasticsearch, redis, …) -->

Prod host ports are allocated per project across the VPS — pick a free range from
<https://stats.overdoser.org/suggest?size=100> (returns 5 candidate port ranges to
claim for a project).

<!-- ============================================================================
Project-specific sections go below — whatever the structure demands, e.g.:

## Browser extension          (how to build/load, where the packaged zip lives)
## Database migrations (Drizzle)   (db:generate / db:migrate / db:seed + schema path)
## Scheduled jobs / CRON
## Admin CLI / maintenance scripts
============================================================================= -->

## Database migrations (Drizzle)

```bash
yarn db:generate   # diff libs/db/src/lib/schema.ts -> libs/db/drizzle/*.sql
yarn db:migrate    # apply
yarn db:seed       # idempotent seed
```

Schema lives in `libs/db/src/lib/schema.ts`. Edit it, then `db:generate`. The prod
`api` container runs migrations on every start (idempotent).
