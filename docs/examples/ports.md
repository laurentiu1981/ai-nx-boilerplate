# Picking ports for a new project

All projects share one host machine, so every project reserves its own port range.
The registry is **`~/GITCRK/PORTS.md`** — read it, pick, then update it.

## The procedure

1. **Read `~/GITCRK/PORTS.md`**, especially section 4 ("Recommended pattern for new
   projects") — it names the next free band.
2. **Claim a full free 100-port band** (`xx00–xx99`) whose two-digit prefix isn't used
   by any existing 4-digit port. Examples of taken bands: 55xx (crk-mind-cache),
   56xx (crk-stocks), 61xx (crk-chat), 63xx (ai-chat), 64xx (crk-agent-gallery).
   The doc's header notes the next free band.
3. **Use the established offsets inside the band** (`{{port_band}}` = the two-digit prefix,
   e.g. `69` for the 6900–6999 band):

   | Offset | Service | Env var |
   |---|---|---|
   | `{{port_band}}10` | web (Next.js) | `WEB_PORT` |
   | `{{port_band}}20` | api (NestJS) | `API_PORT` |
   | `{{port_band}}30` | database (postgres/mysql) | `POSTGRES_PORT` |
   | `{{port_band}}40`, `{{port_band}}41`, … | extras (elasticsearch, redis, minio, …) | per service |
   | `{{port_band}}50` | tools/pgadmin (profile: tools) | `PGADMIN_PORT` |
   | `{{port_band}}70`+ | more extras (mailhog, searxng, …) | per service |

4. **If the project deploys to a shared VPS**, also claim a **prod band in the
   10xxx range** for `{{prod_port_web}}` / `{{prod_port_api}}`. Prod bands are
   allocated across the VPS by asking the allocation service:

   ```bash
   curl -s 'https://stats.overdoser.org/suggest?size=100'
   # {"size":100,"suggestions":[[10500,10599],[10600,10699],[10700,10799],...]}
   ```

   It returns 5 candidate free 100-port ranges — claim the first one and apply the
   same offsets inside it (e.g. band 10500–10599 → web `10510`, api `10520`).
   Prod ports are separate from dev so both stacks can run side by side; prod
   postgres is never published on the host.
   **Record the prod band ONLY in the project's README/CLAUDE.md — NEVER in
   `~/GITCRK/PORTS.md`.** That file registers ports bound on the local machine;
   the VPS is a different machine, and the allocation service above is the
   source of truth for its claims.
5. **Every host port must be `${SOMETHING_PORT:-<default>}`** in compose — never a raw
   literal — so a developer can rebind on collision without editing the compose file.
   Mirror every default in `.env.example`.
6. **Update `~/GITCRK/PORTS.md`** with the DEV band only (prod/VPS ports never go
   in this file): add rows to the port-by-port index (section 1, keep it sorted),
   add the project to the per-project table (section 3), and update the "next free
   band" note in section 4.0 and the header changelog line.
7. **Declare the allocation in the project's README/CLAUDE.md** as a one-line table
   (plus the prod band, which is documented only there) so PORTS.md can be
   regenerated mechanically:

   ```
   | Service | Container | Host port |
   |---------|-----------|-----------|
   | web     | {{project_name|machine_name}}_web      | {{port_band}}10 |
   | api     | {{project_name|machine_name}}_api      | {{port_band}}20 |
   | db      | {{project_name|machine_name}}_postgres | {{port_band}}30 |
   ```

## Avoid the "magnet" ports

Never pick these as defaults: `80, 443, 3000, 3001, 3306, 4200, 5432, 5900, 8000,
8080, 8081, 8443, 9090, 9229`. If tooling expects one (e.g. postgres 5432), keep the
container port standard and map a banded host port to it (`{{port_band}}30:5432`).
