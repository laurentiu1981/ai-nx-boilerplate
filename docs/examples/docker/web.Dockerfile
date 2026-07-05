# Release image for the WEB app — Next.js standalone output (a traced, minimal
# node_modules), runs on plain `node`. Same layering as the api image:
#   3. code      — server.js + .next chunks + static + public
#   2. modules   — the standalone (traced) node_modules
#   1. base      — node + yarn + dumb-init + curl (changes ~never)
#
# Requires `output: 'standalone'` in apps/web/next.config.js.
#
# NEXT_PUBLIC_* are inlined into the client bundle at BUILD time, so they're build
# args (they bake the API origin in). Build on a host with RAM, push, pull on prod:
#   docker build -f docker/web.Dockerfile \
#     --build-arg NEXT_PUBLIC_API_URL=https://{{domain}} \
#     -t {{image_repo}}:web-<tag> .

# ── 1. base ───────────────────────────────────────────────────────────────────
FROM platformatic/node-caged:26.3.1-alpine AS base
RUN apk add --no-cache dumb-init curl \
 && npm install -g yarn@1.22.22 \
 && npm cache clean --force && rm -rf /root/.npm
WORKDIR /app
ENV NODE_ENV=production NX_DAEMON=false NEXT_TELEMETRY_DISABLED=1
# Non-root runtime user — node-caged ships none (mirrors docker/local.Dockerfile).
RUN addgroup -g 1000 -S node && adduser -S node -u 1000 -G node

# ── 2. builder ────────────────────────────────────────────────────────────────
FROM base AS builder
# Keep NODE_ENV=production (from base) so `next build` prerenders with React's
# production runtime — a development env makes the static export crash
# ("useContext of null"). `--production=false` still pulls the build-time devDeps.
RUN apk add --no-cache python3 make g++ git
# Deps cache: install before copying source (a code-only change reuses this).
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production=false
COPY . .
# Client-public config is compiled in here — defaults target prod.
ARG NEXT_PUBLIC_API_URL=https://{{domain}}
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN yarn build:web

# ── 3. runtime ────────────────────────────────────────────────────────────────
FROM base AS runtime
# Layer 2 — traced node_modules (rebuilds only when the traced dep set changes).
COPY --from=builder /app/apps/web/.next/standalone/node_modules ./node_modules
# Layer 3 — server + chunks + static + public (rebuilds on any code change). Next
# emits `static` and `public` outside the standalone tree, so place them where the
# standalone server expects to find them.
COPY --from=builder /app/apps/web/.next/standalone/apps ./apps
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder /app/apps/web/public ./apps/web/public
# Give the non-root user a writable cache dir (Next writes here for ISR / image
# optimization); everything else is read-only by design.
RUN mkdir -p apps/web/.next/cache && chown -R 1000:1000 apps/web/.next/cache
USER 1000
ENV PORT={{prod_port_web}} HOSTNAME=0.0.0.0
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "apps/web/server.js"]
