# Stack variations — drop-in compose services

The dev compose template (`docker/docker-compose.yml`) ships the core trio
(postgres, api, web). Different projects swap or add services; these are the
proven blocks from existing projects. Host ports follow the band offsets from
`ports.md` (`{{port_band}}40`+ for extras). Gate anything optional behind a compose
`profile` so `docker compose up -d` stays lean.

Shared conventions for every block:
- host ports always `${VAR:-default}`, mirrored in `.env.example`;
- inside the network, services reach each other by service name
  (`postgres:5432`, `redis:6379`, `elasticsearch:9200`, `minio:9000`);
- `extra_hosts: host.docker.internal:host-gateway` on the api lets it reach
  host-run services (LM Studio, vLLM, ComfyUI).

## Postgres variants

**Plain** (default): `postgres:16-alpine`.

**TimescaleDB** (time-series data — crk-stocks): swap the image and tune locks:

```yaml
  postgres:
    image: timescale/timescaledb:latest-pg15
    # Hypertable inserts spanning many chunks take a lock per chunk; a large
    # backfill exhausts the default 64-lock table and surfaces as
    # "out of shared memory" mid-insert.
    command: [postgres, -c, max_locks_per_transaction=1024]
```

**Init dumps**: mount `./docker/postgres/dump:/docker-entrypoint-initdb.d` to load
SQL on first boot.

## No database — filesystem storage

For small apps, skip postgres entirely and persist to a named volume or bind mount:
`- api_data:/app/data` (named volume, dev) or `- ./data:/app/data` (bind mount,
prod — the only state to back up). crk-stocks uses this pattern for uploads
(`UPLOAD_PATH=/app/uploads`, `api_uploads` volume) alongside postgres.

## Elasticsearch (search — crk-mind-cache, crk-stocks, ai-chat)

```yaml
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:9.2.0
    container_name: {{project_name|machine_name}}_elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - 'ES_JAVA_OPTS=-Xms512m -Xmx512m'
    ports:
      - '${ELASTICSEARCH_PORT:-{{port_band}}40}:9200'
      - '${ELASTICSEARCH_TRANSPORT_PORT:-{{port_band}}41}:9300'
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - {{project_name|machine_name}}_network
    healthcheck:
      test: ['CMD-SHELL', 'curl -fsS http://localhost:9200/_cluster/health || exit 1']
      interval: 30s
      timeout: 10s
      retries: 5
```

Design it as an **enhancement, not a dependency**: the api should degrade to a
postgres `ILIKE` search when ES is unreachable, and `depends_on` should use
`condition: service_started` (not `service_healthy`) so a slow ES never blocks the
api. Index is rebuilt from postgres (`yarn index-es`, idempotent).

### Prod: shared Elasticsearch on the VPS (crk-vps-shared pattern)

ES is memory-hungry, so in prod projects do NOT run their own — they share one
instance from the `crk-vps-shared` stack (a separate repo/checkout on the VPS).
That stack owns a fixed-name external docker network and the projects attach to it:

```yaml
# crk-vps-shared/docker-compose.yml (started once, before any project stack):
#   container_name: shared_elasticsearch, network: crk_vps_shared (fixed name),
#   heap capped (ES_JAVA_OPTS=-Xms256m -Xmx256m, mem_limit 768m),
#   host port bound to 127.0.0.1 only (debugging; containers use the network).
```

In the project's `docker-compose-prod.yml`, the api joins the shared network and
uses a **per-project index** so data never collides:

```yaml
  api:
    environment:
      # Unset ELASTICSEARCH_URL to fall back to Postgres search.
      - ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://shared_elasticsearch:9200}
      - ELASTICSEARCH_INDEX=${ELASTICSEARCH_INDEX:-{{project_name|machine_name}}_main}
    networks:
      - {{project_name|machine_name}}_network
      - crk_vps_shared

networks:
  # Owned by the crk-vps-shared stack — start that first (it creates the network).
  crk_vps_shared:
    external: true
```

## Redis (cache — ai-chat)

```yaml
  redis:
    image: redis:7-alpine
    container_name: {{project_name|machine_name}}_redis
    command: ['redis-server', '--appendonly', 'yes']
    ports:
      - '${REDIS_PORT:-{{port_band}}42}:6379'
    volumes:
      - redis_data:/data
    networks:
      - {{project_name|machine_name}}_network
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 10s
      timeout: 5s
      retries: 5
```

api env: `REDIS_URL=redis://redis:6379`. ai-chat uses it as a cache layer over
postgres (assembled prompt context, 1h TTL). Note: for single-instance GraphQL
subscriptions an in-process `PubSub` is enough (crk-stocks) — add Redis only when
you need cross-instance messaging or a real cache.

## MinIO (S3-compatible object storage — ai-chat)

The alternative to filesystem uploads when you want an S3 API:

```yaml
  minio:
    image: minio/minio:latest
    container_name: {{project_name|machine_name}}_minio
    # Run as your host user so files under the bind mount are owned by YOU, not
    # root. PRE-CREATE the data dir so docker doesn't create it root-owned.
    user: '${MINIO_UID:-1000}:${MINIO_GID:-1000}'
    command: ['server', '/data', '--console-address', ':9001']
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER:-{{project_name|machine_name}}}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-{{project_name|machine_name}}_minio_secret}
    ports:
      - '${MINIO_PORT:-{{port_band}}44}:9000'
      - '${MINIO_CONSOLE_PORT:-{{port_band}}45}:9001'
    volumes:
      - ${MINIO_DATA_DIR:-./docker/minio/data}:/data
    networks:
      - {{project_name|machine_name}}_network
```

api env: `MINIO_ENDPOINT=minio`, `MINIO_PORT=9000`, `MINIO_USE_SSL=false`, bucket
name, and access/secret mirroring the root user/password. Serve stored objects
through an api proxy route; build URLs from `API_PUBLIC_URL` for the browser and an
internal `http://api:<port>/api` URL for in-network consumers.

## MailHog (dev SMTP catcher — crk-stocks, profile: mail-dev)

```yaml
  mailhog:
    image: mailhog/mailhog:latest
    container_name: {{project_name|machine_name}}_mailhog
    profiles: ['mail-dev']
    ports:
      - '${MAILHOG_UI_PORT:-{{port_band}}70}:8025'
      - '${MAILHOG_SMTP_PORT:-{{port_band}}71}:1025'
    networks:
      - {{project_name|machine_name}}_network
```

Pattern: when `MAILGUN_API_KEY` (or your real provider's key) is unset, the api
routes mail via SMTP to `mailhog:1025`.

## SearXNG (self-hosted web search for AI tool loops — crk-stocks)

```yaml
  searxng:
    image: searxng/searxng:latest
    container_name: {{project_name|machine_name}}_searxng
    environment:
      - SEARXNG_BASE_URL=http://localhost:${SEARXNG_PORT:-{{port_band}}80}/
      - SEARXNG_SECRET=${SEARXNG_SECRET:-{{project_name|slug}}-searxng-dev-secret}
    volumes:
      - ./docker/searxng/settings.yml:/etc/searxng/settings.yml:ro
    ports:
      - '${SEARXNG_PORT:-{{port_band}}80}:8080'
    networks:
      - {{project_name|machine_name}}_network
    restart: unless-stopped
```

The api reaches it at `http://searxng:8080` and GETs `/search?q=…&format=json`.
No API key, fully local; the host port is only for eyeballing results.

## vLLM (GPU LLM inference — ai-chat, profile: gpu)

Default to a **host-run** vLLM (`VLLM_BASE_URL=http://host.docker.internal:8000/v1`)
and offer an in-compose GPU service as opt-in (`docker compose --profile gpu up -d`,
needs nvidia-container-toolkit). Key details from ai-chat's `docker/vllm.Dockerfile`
+ compose block: run as host uid/gid, mount the host's HF cache
(`~/.cache/huggingface`) so model weights are reused, create an /etc/passwd entry
for uid 1000 (libraries calling `getpwuid()` crash without one), and remember engine
args are boot-time only. See `ai-chat` for the full block.

## Other backing-service patterns seen in the fleet

- mongo (crk-postman, profile: db), coturn for WebRTC (crk-chat, profile: video).
- **Admin/maintenance jobs**: token-gated internal endpoints (`x-admin-token`)
  triggered by a small host-side script that `docker compose exec`s into the api
  (crk-stocks `scripts/sync-internal.sh`).
- **Secrets at rest**: user-supplied API keys encrypted with a dedicated
  `ENCRYPTION_KEY` (AES-256-GCM), deliberately independent from `JWT_SECRET` so
  rotating auth can't orphan stored data (crk-stocks).
