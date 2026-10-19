# Robinah’s Shop — Phoenix + LiveView

An Elixir/Phoenix implementation of the public Robinah’s Shop app at
https://robinah-s-shop-qlr4ne.v2.appdeploy.ai/.

**Provenance:** this is a new Phoenix/LiveView port based on the recovered public browser bundle, stylesheet and images. The connected AppDeploy account did not authorise access to the original source snapshot. Original server source, staff accounts, passwords, private inventory and transaction history have **not** been extracted. See `PROVENANCE.md` and `reference/`.

## Included

- Original shop branding, photos, public-page copy, collections, search, category filters and WhatsApp enquiry basket, rendered with HEEx and LiveView.
- Persistent PostgreSQL inventory through Ecto (`robinah_dev` in local development); one application container plus a PostgreSQL service in Docker Compose.
- Staff sign-in with hashed passwords, encrypted session cookies, expiring/revocable sessions, login throttling, and server-side role checks.
- Owner: all tools and staff account creation/deactivation. Manager: products, receiving, sales and reports. Cashier: sales. Receiver: goods receiving.
- Product/price editing, atomic receiving and sales, server-calculated prices, stock checks, whole-UGX money, replay-safe request identifiers, server-confirmed receipts and receipt printing.
- Reports over the entire selected date range, product/payment summaries and CSV export. Date filters and display use East Africa Time (UTC+3).
- Linux release Dockerfile, Docker Compose, optional Caddy TLS proxy, existing Nginx integration example, health check and consistent database backup script.

The six supplied catalogue entries remain **illustrative**, with zero prices and zero stock. Configure real prices and receive actual quantities before selling. WhatsApp opens a draft for the visitor to send. Card and mobile-money choices are **manual payment records**; no payment-gateway integration is included.

## Local development (WSL or Linux)

Requires Elixir 1.18+ / compatible Erlang/OTP, Hex, Rebar and a running PostgreSQL server (the development database is named `robinah_dev`; connection settings can be overridden with `PGUSER`, `PGPASSWORD`, `PGHOST`, `PGPORT` and `PGDATABASE`). Elixir 1.19 is used by the Docker build. No Node, React or JavaScript bundler is required.

```bash
cd /path/to/robinahs_shop
mix local.hex --force
mix local.rebar --force
mix setup

# Choose the owner's credentials; this does not change an existing owner.
read -r -p 'Owner email: ' ADMIN_EMAIL
read -r -s -p 'Owner password (16+ characters): ' ADMIN_PASSWORD
printf '\n'
export ADMIN_EMAIL ADMIN_PASSWORD
mix run priv/repo/seeds.exs
unset ADMIN_PASSWORD
mix phx.server
```

Open http://localhost:4000. Staff sign-in is `/staff/sign-in`. Use Products & prices to configure items, then Goods receiving to record opening quantities.

```bash
mix format --check-formatted
mix test
```

## Deploy to your VPS

Copy this directory or unzip the source archive into a **new directory**, for example `/opt/robinahs_shop`. It is independent of `/home/aidomex/Omfix`. Docker Engine with the Compose plugin must already be installed.

```bash
cd /opt/robinahs_shop
bash scripts/init-env.sh
bash scripts/deploy.sh
```

The initializer asks for your domain and owner email, then generates secrets locally and creates a private `.env`. Keep the displayed owner password securely. No production secrets are included in this source package.

The default deployment binds the app only to `127.0.0.1:4100`. This avoids competing for your existing VPS web ports. Point the shop domain's DNS at the VPS and connect the existing HTTPS proxy:

- Nginx: use `deploy/nginx.conf.example` within a shop-specific HTTPS virtual host. Keep the WebSocket and forwarded-protocol headers.
- Existing Caddy: `shop.example.com { reverse_proxy 127.0.0.1:4100 }`.
- Existing Traefik: route the shop hostname to port 4000 on the app's Docker network; configure TLS and WebSocket forwarding.

If the VPS has **no existing listener on ports 80/443**, the optional bundled Caddy can manage HTTPS:

```bash
bash scripts/deploy.sh --edge
```

Set `PHX_HOST` to the exact public hostname, without scheme or path. Production LiveView accepts only that HTTPS origin and uses secure cookies. Keep port 4100 private; use HTTPS for staff access. Open ports 80/443 when using Caddy. Do not expose Erlang distribution ports.

```bash
# Status and logs

docker compose ps
docker compose logs --tail=100 app
curl -fsS http://127.0.0.1:4100/healthz

# Update after replacing the source; named data volume is retained
bash scripts/deploy.sh

# Backup the live database consistently
bash scripts/backup.sh
```

If Caddy was enabled, also use the edge deployment option for later updates. The Caddy service and certificates persist until explicitly removed.

## Deploy to Render (Dockerised release)

The repository ships a `render.yaml` blueprint: a Docker web service built from the root `Dockerfile`, plus an external PostgreSQL server (the blueprint provisions no database of its own). The container runs the OTP release; `scripts/docker-entrypoint.sh` applies migrations, seeds the 36 catalogue rows and bootstraps the owner before `bin/robinahs_shop start`.

1. Generate the secrets first: `bash scripts/init-env.sh` (or `openssl rand -hex 64` for `SECRET_KEY_BASE`, a random password of 16+ characters for `ADMIN_PASSWORD`).
2. Render Dashboard → **New → Blueprint** → connect `Aidomex-Group-Ltd/Robinah` → keep the root directory `/` and confirm `render.yaml`.
3. On first sync, fill the prompted values: `DATABASE_URL` (the complete URL of your PostgreSQL server, see below), `SECRET_KEY_BASE` (64+ bytes), `ADMIN_EMAIL`, `ADMIN_PASSWORD`.
4. Deploy. The service listens on `PORT` 10000 and `PHX_HOST` is derived automatically from `RENDER_EXTERNAL_HOSTNAME`; `DATABASE_URL` is the value entered at the first sync — it is kept across later syncs and never written to git.
5. On an **existing** service, `sync: false` variables are not re-prompted: set `DATABASE_URL` (and any rotated secret) by hand in **Environment**, then deploy. A blueprint update never overwrites a variable that already exists.
6. If you had previously linked a Render Postgres instance through this blueprint, the sync now offers to delete it (`robinahs-shop-db` is no longer in `render.yaml`). Decline until its contents are no longer needed.

`DATABASE_URL` is a complete URL with scheme, host, port and database name:

- External server (Aiven, RDS, DigitalOcean, …): `postgresql://user:password@host:5432/database?sslmode=require`. TLS is required — without `sslmode=require` the release refuses to start, because Postgrex would otherwise open a plain TCP connection to a TLS-only port. `sslmode=verify-ca`/`verify-full` additionally validate the certificate chain against the OS CA store.
- Render Postgres in the same region: the instance's **Internal** URL (`postgresql://user:pass@host.render.internal:5432/database`, no `sslmode`). It only resolves when the database shares the service's region; an external URL removes that constraint.

Manual equivalent, for the New Web Service page: a Docker web service from this repository (runtime **Docker**, root directory `/`, health check path `/healthz`) and set the variables listed below by hand. The service derives its hostname from Render, so `PHX_HOST` must be left unset.

| Variable | Required | Value |
| --- | --- | --- |
| `DATABASE_URL` | yes | complete URL of the PostgreSQL server: an external one needs `?sslmode=require`, a Render internal one has no `sslmode` and must be same-region |
| `SECRET_KEY_BASE` | yes | 64+ bytes, e.g. `openssl rand -hex 64`; remove any `SECRET_BASE_KEY`, which takes precedence when both exist |
| `ADMIN_EMAIL` | yes, on a new database | owner sign-in email, e.g. `owner@example.com`; ignored once an owner exists |
| `ADMIN_PASSWORD` | yes, on a new database | 16–128 characters, e.g. `openssl rand -base64 24`; ignored once an owner exists |
| `PHX_HOST` | no | **unset it**: the release falls back to `RENDER_EXTERNAL_HOSTNAME`. Only set it for a custom domain, as a bare hostname |
| `PHX_SERVER` | no | `true` (the image already sets it) |
| `PORT` | no | `10000` is what Render sends; must be a positive integer |
| `POOL_SIZE` | no | `5` (defaults to `10`); must be a positive integer |
| `JWT_SECRET` | yes | staff session digest secret; the blueprint generates it, or `openssl rand -hex 32` |
| `LIVE_SIGNING_SALT` | yes | LiveView signing salt; the blueprint generates it, or `openssl rand -hex 16` |
| `ERL_FLAGS` | no | `+S 2:2` to cap schedulers on small instances |

If the service exits with a `Cannot start Robinah's Shop` message, the release lists every missing or invalid variable — add them in **Environment**, then redeploy. `DATABASE_URL`, `SECRET_KEY_BASE`, `JWT_SECRET`, `LIVE_SIGNING_SALT`, `POOL_SIZE` and `PORT` are all checked before the release opens a socket. On a **new** database `ADMIN_EMAIL` and `ADMIN_PASSWORD` are verified before the owner account is created, so a deploy stops with an explicit message instead of leaving a shop nobody can sign in to; a database that already has an owner is never modified, so those two values can be removed from an existing service.

Notes:

- The web service region is fixed at creation time (`render.yaml` uses `region: oregon`). Because `DATABASE_URL` now points outside Render, the database no longer has to be in that region; only a Render-internal URL still requires both to match.
- The `free` plan spins down after 15 minutes of inactivity and resumes in about a minute; upgrade it for a real shop. TLS and the WebSocket upgrade are terminated by Render, so staff LiveView works on the `onrender.com` domain without extra proxy configuration.
- Pushes to `main` trigger an automatic rebuild. Migrations and seeds run on every container start and are idempotent; existing owner passwords and products are never overwritten.

## Data, backups and accounts

PostgreSQL data lives on the `db_data` named volume and is served by the bundled `db` service (PostgreSQL 16). Migrations and missing illustrative catalogue entries are applied at startup. Existing owner passwords and existing products are not overwritten. Removing the named volume deletes the database.

`backup.sh` runs `pg_dump -Fc` against the live database service. Copy backups off the VPS. Test restores on a separate deployment before replacing live data.

Owner-only Staff accounts creates manager, cashier and receiver accounts. To reset/reactivate a staff account from the VPS, set `NEW_STAFF_PASSWORD` temporarily and invoke the release helper with the exact email. This revokes its previous sessions. Example inside the container (the email is an Elixir string, so use your real email):

```bash
# Run in Bash on the VPS host; substitute the account's real email below.
read -r -s -p 'New staff password (16+ characters): ' NEW_STAFF_PASSWORD
printf '\n'
export NEW_STAFF_PASSWORD
docker compose exec -e NEW_STAFF_PASSWORD app /app/bin/robinahs_shop eval 'RobinahsShop.Release.reset_password("owner@example.com")'
unset NEW_STAFF_PASSWORD
```

Existing passwords are never recovered from the original app. Revoked LiveView sessions are checked again before events, navigation and server updates.

## Structure

- `lib/robinahs_shop/`: accounts, Ecto schemas, transactional shop context and release helpers.
- `lib/robinahs_shop_web/live/`: public and staff LiveViews with editable `.html.heex` frontends.
- `assets/`: original stylesheet plus small LiveView additions; ES module entry point.
- `priv/static/resources/`: original logo/photo and local copies of illustrative category images.
- `priv/repo/`: schema migration and safe, repeatable catalogue seeds.
- `deploy/`, `scripts/`, `compose*.yml`, `Dockerfile`, `render.yaml`: VPS and Render deployment.
- `test/`: business-rule, session and HTTP access tests.
- `reference/`: recovered public browser artifacts and asset provenance, excluded from the container.

`mix assets.deploy` copies the browser clients from the exact locked Phoenix/LiveView dependencies into `priv/static/assets` and fingerprints static assets. It requires no npm installation. Linux releases are built on the VPS/container; a Windows build must not be copied to a Linux VPS.

See `VALIDATION.md` for the checks actually completed in this environment and outstanding verification.
# Robinah
