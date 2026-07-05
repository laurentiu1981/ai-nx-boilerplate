# Release process (registry-based, domain-agnostic)

This is the release flow used by `crk-mind-cache` / `crk-agent-gallery`, generalized.
Copy the three scripts from `scripts/` into the new project's `scripts/` directory,
replace the `{{...}}` placeholders, and wire the npm scripts below.

## Principles

- **Never build on the VPS.** The webpack (NestJS) and Next.js builds are memory-heavy;
  build on a dev machine or CI, push to a registry, and only `pull` on the server.
- **Two kinds of tags per image:**
  - *pinned* — `{{image_repo}}:api-<git-short-sha>` / `{{image_repo}}:web-<git-short-sha>`,
    immutable, for pinning and rollback;
  - *floating* — `{{image_repo}}:api` / `{{image_repo}}:web`, always the latest release,
    what the prod compose pulls by default.
- **Migrations run on container boot.** The api image's CMD is
  `node migrate.js && node main.js` — the Drizzle migration runner is idempotent, so
  every deploy applies pending migrations before serving. No separate migration step.
- **One-command rollback window.** The pull script tags the currently-running images
  `<ref>-bak` before pulling; until you prune, rollback is retag + restart.

## npm scripts to add to package.json

```json
{
  "docker:release": "./scripts/docker-release.sh",
  "docker:release:pull": "./scripts/docker-release-pull.sh",
  "docker:prune": "./scripts/docker-prune.sh",
  "prod:start": "docker compose -f docker-compose-prod.yml up -d"
}
```

## The flow

On the **build host** (dev machine or CI, after `docker login`):

```bash
yarn docker:release            # tag = git short SHA
yarn docker:release v1.4.2     # or an explicit tag
```

This builds `docker/api.Dockerfile` and `docker/web.Dockerfile`, pushes the pinned
tags, then moves the floating `:api` / `:web` tags to the same images.
`NEXT_PUBLIC_*` values are **baked into the web image at build time** (they are
inlined into the client bundle), so a domain / API-origin change requires a rebuild.

On the **VPS**:

```bash
yarn docker:release:pull       # back up current images as <ref>-bak, then pull
yarn prod:start                # recreate containers from the new images
# ...verify the site is healthy...
yarn docker:prune              # drop the -bak backups (removes one-command rollback)
```

**Rollback** (before pruning):

```bash
docker tag {{image_repo}}:api-bak {{image_repo}}:api
docker tag {{image_repo}}:web-bak {{image_repo}}:web
yarn prod:start
```

Or pin a known-good sha in the VPS `.env`:

```bash
API_IMAGE={{image_repo}}:api-<sha>
WEB_IMAGE={{image_repo}}:web-<sha>
```

## First deploy on a fresh VPS

1. Install docker + compose plugin; `docker login` to the registry.
2. If the project uses shared VPS services (e.g. the shared Elasticsearch — see
   `../stacks.md`), start the `crk-vps-shared` stack first; it owns the external
   `crk_vps_shared` network the api attaches to:
   ```bash
   cd <path-to>/crk-vps-shared && docker compose up -d
   ```
3. Clone the repo (only compose files, scripts and `.env` are needed at runtime —
   the images are self-contained).
4. `cp .env.prod.example .env` and fill the required secrets
   (`JWT_SECRET`, `POSTGRES_PASSWORD`, Google OAuth creds if used).
5. `yarn docker:release:pull && yarn prod:start`
6. Configure the reverse proxy for `{{domain}}` (see `../reverse-proxy.md`)
   and issue certificates (certbot / Caddy automatic).

Note: build-host CPU arch must match the VPS (x86_64) — on ARM build with
`docker buildx --platform linux/amd64`.

## Placeholders used by the templates

| Placeholder | Meaning | Example |
|---|---|---|
| `{{image_repo}}` | Registry repo for both images | `dockerhubuser/{{project_name\|slug}}` |
| `{{domain}}` | Public production domain | `myapp.example.com` |
| `{{project_name\|machine_name}}` | Snake-case prefix (containers, db, network) | `my_app` |
| `{{project_name\|slug}}` | Kebab-case slug | `my-app` |
| `{{prod_port_web}}` / `{{prod_port_api}}` | Prod host ports — pick a free 10xxx band per `../ports.md` | `10210` / `10220` |
