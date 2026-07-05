# Postgres + Drizzle setup (schema, migrations, seeding)

The pattern from crk-mind-cache / crk-agent-gallery: schema and migrations live in a
shared Nx lib (`libs/db` or `libs/database`), driven by `drizzle-kit`.

## Files

- `drizzle.config.ts` (repo root):

```ts
import { defineConfig } from 'drizzle-kit';

/**
 * drizzle-kit reads this to generate and run SQL migrations.
 *   yarn db:generate  → diff schema.ts against ./libs/db/drizzle, emit SQL
 *   yarn db:migrate   → apply pending migrations (see libs/db/src/migrate.ts)
 */
export default defineConfig({
  schema: './libs/db/src/lib/schema.ts',
  out: './libs/db/drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL ?? '' },
  verbose: true,
  strict: true,
});
```

- `libs/db/src/lib/schema.ts` — the single source of truth for tables.
- `libs/db/src/lib/client.ts` — `createDb(connectionString, max)` using `postgres`
  (postgres-js) + `drizzle-orm/postgres-js`.
- `libs/db/drizzle/` — generated SQL migrations + `meta/` journal (committed).
- `libs/db/src/migrate.ts` — standalone runner: `drizzle-orm/postgres-js/migrator`
  with `migrationsFolder: 'libs/db/drizzle'`, single connection (`createDb(url, 1)`),
  `sql.end()` when done. Keep it decorator-free — it gets esbuild-bundled for prod.
- `libs/db/src/seed.ts` — idempotent seeding (safe to run on every boot).

## package.json scripts

```json
{
  "db:generate": "drizzle-kit generate",
  "db:migrate": "tsx libs/db/src/migrate.ts",
  "db:seed": "tsx libs/db/src/seed.ts"
}
```

## How migrations run

- **Dev** — the api container's startup command chains
  `yarn install → db:generate → db:migrate → db:seed → dev:api`
  (generate/seed tolerantly wrapped in `|| echo skipped` — see the dev compose template).
- **Prod** — the api image bundles `migrate.js` (esbuild, `--packages=external`) and
  copies the `libs/db/drizzle` SQL in; the container CMD is
  `node migrate.js && node main.js`, so pending migrations apply on every container
  boot, idempotently. **Seeding is not run in prod.**
