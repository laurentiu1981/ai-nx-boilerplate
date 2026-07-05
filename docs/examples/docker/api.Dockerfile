# Release image for the API (NestJS) — bundled (no ts-node-dev at runtime), slim,
# and layered so a code-only change reships ONE layer, a dependency change TWO.
#
# `nx build api` runs webpack with `compiler: 'tsc'` (apps/api/webpack.config.js):
# tsc preserves the `emitDecoratorMetadata` reflection Nest's DI needs (esbuild
# can't), so the whole app — including the workspace libs — bundles into a single
# self-contained dist/apps/api/main.js, no runtime alias resolver required.
# `generatePackageJson` emits the PRUNED dist/apps/api/{package.json,yarn.lock} —
# only the deps the bundle imports — for a slim, reproducible production install.
# esbuild is used ONLY for the standalone migration runner (plain script, no
# decorators → safe to bundle; deps left external, resolved at runtime).
#
# Layers in the final image (top = changes most often):
#   3. code      — COPY of dist/apps/api (bundled main.js + migrate.js) + drizzle SQL
#   2. modules   — COPY of the PRUNED production node_modules (generated manifest)
#   1. base      — node + yarn + dumb-init (changes ~never)
#
# Build (needs RAM for the webpack/tsc build — do it on a capable host/CI, not the VPS):
#   docker build -f docker/api.Dockerfile -t {{image_repo}}:api-<tag> .
# Run:
#   docker run --env-file .env -p {{prod_port_api}}:{{prod_port_api}} {{image_repo}}:api-<tag>

# ── 1. base ───────────────────────────────────────────────────────────────────
# Shared by every stage. node-caged ships only npm (no corepack/yarn), so add yarn.
FROM platformatic/node-caged:26.3.1-alpine AS base
# Clean the npm cache here: this layer is inherited by the runtime stage, so its
# cache would otherwise ship. (Caches in builder/proddeps don't — those stages are
# discarded; only their node_modules/dist get COPY --from'd.)
RUN apk add --no-cache dumb-init curl \
 && npm install -g yarn@1.22.22 \
 && npm cache clean --force && rm -rf /root/.npm
WORKDIR /app
ENV NODE_ENV=production NX_DAEMON=false NEXT_TELEMETRY_DISABLED=1
# Non-root runtime user — node-caged ships none (mirrors docker/local.Dockerfile).
RUN addgroup -g 1000 -S node && adduser -S node -u 1000 -G node

# ── 2. builder ────────────────────────────────────────────────────────────────
# Full (dev) install + compile. Fat, but discarded — never shipped.
FROM base AS builder
ENV NODE_ENV=development
RUN apk add --no-cache python3 make g++ git
# Deps cache: install before copying source, so a code-only change reuses this.
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
# Source + build. `nx build api` (webpack) emits the bundled main.js + the pruned
# package.json/yarn.lock. esbuild compiles the standalone migration runner separately
# (deps left external → resolved at runtime against the pruned node_modules).
COPY . .
RUN yarn build:api \
 && node_modules/.bin/esbuild libs/database/src/migrate.ts \
      --bundle --platform=node --format=cjs --packages=external \
      --outfile=dist/apps/api/migrate.js

# ── 3. prod deps ──────────────────────────────────────────────────────────────
# Install ONLY the deps the bundle actually imports (from the generated manifest).
# Cache key = the pruned package.json/yarn.lock → unchanged when only code changes.
FROM base AS proddeps
COPY --from=builder /app/dist/apps/api/package.json /app/dist/apps/api/yarn.lock ./
# The generated package.json + yarn.lock are self-consistent, so frozen works.
# (No cache-clean needed — this stage is discarded; only node_modules is copied.)
RUN yarn install --production --frozen-lockfile

# ── 4. runtime ────────────────────────────────────────────────────────────────
FROM base AS runtime
# Layer 2 — production modules (rebuilds only when the pruned deps change).
COPY --from=proddeps /app/node_modules ./node_modules
# Layer 3 — bundled app + migration runner + drizzle SQL (rebuilds on any code change).
COPY --from=builder /app/dist/apps/api ./
COPY --from=builder /app/libs/database/migrations ./libs/database/migrations
# Drop root. The bundled app is read-only on disk EXCEPT /app/uploads (if the app
# stores uploaded files) — pre-create it owned by 1000 (covers the no-bind-mount
# case; with the compose bind-mount, also `chown -R 1000:1000 ./uploads` on the host).
RUN mkdir -p uploads && chown 1000:1000 uploads
USER 1000
ENTRYPOINT ["dumb-init", "--"]
# Apply migrations (idempotent) then serve — both plain `node`, no ts-node-dev, no source.
CMD ["sh", "-c", "node migrate.js && node main.js"]
