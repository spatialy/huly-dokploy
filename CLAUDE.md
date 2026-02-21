# CLAUDE.md - Huly V7 Dokploy Template

## Project Overview

Dokploy blueprint template for self-hosting [Huly V7](https://huly.io/) — an all-in-one project management platform. The template's core value is a **session persistence fix** that prevents the logout-on-refresh bug in Huly V7 behind reverse proxies.

Forked from `shali1995/huly-dokploy-fucking-working`. Three blueprints are available:

- **`huly-v7`** (v1.1.2) — Legacy blueprint using `haiodo/*` images at v0.7.315 (from the intabia-fusion PostgreSQL fork). Stable fallback.
- **`huly-v7-next`** (v3.0.0+) — Uses official `hardcoreeng/*` upstream images at v0.7.353 on CockroachDB (matching the official upstream). Full service stack including `kvs`, `calendar`, `gmail`, `telegram-bot`, `link-preview`, `aibot` + MongoDB, and `love-agent` (meeting transcription). **Breaking change from v2.x** — migrated from PostgreSQL to CockroachDB.
- **`huly-v7-pg`** (v3.2.0+) — Same as `huly-v7-next` but uses **PostgreSQL 17** instead of CockroachDB. Saves ~1-1.5GB RAM. Uses `CREATE DOMAIN bytes AS bytea;` for KVS compatibility and `PROCEED_V7_MONGO=false` on account service. Recommended for small VPS deployments.

## Repository Structure

```
meta.json                              # Blueprint registry: huly-v7, huly-v7-next, huly-v7-pg
README.md                              # User-facing deployment guide
scripts/bump-version.sh                # Bump template version across all files
blueprints/huly-v7/                    # Dokploy: haiodo/* v0.7.315 (legacy)
  template.toml                        # Dokploy template: variables, env, domains, mounted files
  docker-compose.yml                   # 29 services orchestration (including LiveKit)
  huly.svg                             # Logo for Dokploy UI
blueprints/huly-v7-next/               # Dokploy: hardcoreeng/* v0.7.353 on CockroachDB
  template.toml                        # Same structure, official upstream images
  docker-compose.yml                   # 40 services (CockroachDB, kvs, calendar, gmail, telegram, love-agent, backup, export, notification, sign, cockroach-jobs)
  huly.svg                             # Logo for Dokploy UI
blueprints/huly-v7-pg/                 # Dokploy: hardcoreeng/* v0.7.353 on PostgreSQL (recommended)
  template.toml                        # PostgreSQL variant (bytes domain alias for kvs)
  docker-compose.yml                   # 40 services (PostgreSQL, kvs, calendar, gmail, telegram, love-agent, backup, export, notification, sign, pg-jobs)
  huly.svg                             # Logo for Dokploy UI
coolify/
  huly-v7-next/                        # Coolify / Docker Compose: CockroachDB deployment
    docker-compose.yml                 # Self-contained compose (same 40 services, ./volumes/ paths)
    .env.example                       # Documented env template with secret generation commands
    volumes/                           # Config files extracted from template.toml inline mounts
      nginx/entrypoint.sh              # Parent-domain calc + sed replacement
      nginx/huly.nginx.conf            # Nginx config template (with placeholders)
      livekit/entrypoint.sh            # Placeholder replacement + exec livekit-server
      livekit/livekit.yaml             # LiveKit config template
      love-agent/entrypoint.sh         # JWT generation + exec node index.js start
      cockroach-jobs/reconcile.sh      # Meeting-minutes counter reconciliation
      sign/entrypoint.sh               # Auto-generates self-signed PKCS#12 cert
  huly-v7-pg/                          # Coolify / Docker Compose: PostgreSQL deployment (recommended)
    docker-compose.yml                 # Self-contained compose (40 services on PostgreSQL)
    .env.example                       # Documented env template
    volumes/                           # Config files
      nginx/                           # Same nginx config
      livekit/                         # Same livekit config
      love-agent/                      # Same love-agent entrypoint
      postgres/init-kvs.sql            # CREATE DOMAIN bytes AS bytea (kvs compatibility)
      pg-jobs/reconcile.sh             # Meeting-minutes counter reconciliation (PostgreSQL)
      sign/                            # Same sign entrypoint
  huly.yaml                            # Coolify upstream template (single file, SERVICE_* magic vars)
```

**Dokploy**: `template.toml` is the single source of truth — it contains the nginx config, entrypoint script, and livekit.yaml as inline `[[config.mounts]]` entries.

**Coolify / Docker Compose**: `coolify/huly-v7-next/` contains standalone files extracted from `template.toml`. The `docker-compose.yml` uses `./volumes/` relative paths instead of `../files/volumes/`. Works with Coolify (Git repo deployment), Portainer, Dockge, or bare `docker compose up`. The `coolify/huly.yaml` is a single-file Coolify service template with `SERVICE_*` auto-generated secrets and inline `content:` directives.

## Architecture

### Single Blueprint Design

One Dokploy blueprint contains everything — Huly + LiveKit in a single compose stack. Only **one domain** is needed. LiveKit signaling is proxied through nginx at `/livekit/`, while TURN/media ports are exposed directly on the host via Docker port mapping.

### Service Layers

All traffic enters through **nginx:80**, which routes by URL path prefix:

| Layer | Services |
|-------|----------|
| **Proxy** | nginx (routes `/_<name>` and `/livekit/` paths to backends) |
| **Infrastructure** | cockroachdb:26257 (huly-v7-next) / postgres:5432 (huly-v7), redis:8.0, redpanda:v25.2.11 (Kafka), minio (S3), elastic:7.14.2, mongo:27017, livekit (WebRTC) |
| **Core** | account:3000, transactor:3333, front:8080, workspace, collaborator:3078, fulltext:4700, kvs:8094 |
| **Feature** | love:8097 (video), love-agent (transcription), aibot:4010 (AI), stats:4900, hulypulse:8098, stream:1081, media, preview:4043, datalake:4031, rekoni:4004, print:4005, github:3500, mail:8097, rating, process-service, link-preview:4041, notification:8091 (push), backup (scheduler), backup-api:4039 (download), export:4009, sign:4006 (PDF) |
| **Integrations** | calendar:8095 (Google Calendar), gmail:8087 (Gmail), telegram-bot:8086 (Telegram) |
| **Maintenance** | cockroach-jobs (meeting-minutes counter reconciliation) |

### Database Architecture

**huly-v7-pg (v3.2.0)** uses **PostgreSQL 17** (`postgres:17-alpine`). Upstream added PostgreSQL support in PR #10331 (Dec 2025), included in v0.7.353. Uses `PROCEED_V7_MONGO=false` on account to skip MongoDB migration path. Saves ~1-1.5GB RAM vs CockroachDB. MongoDB is still used by `aibot` and `calendar`. **Known issue:** `kvs` (hulykvs) crash-loops on PostgreSQL — the `CREATE DOMAIN bytes AS bytea` fixes the DDL migration, but the Rust runtime also has CockroachDB-specific SQL (`SET search_path TO $1`, `ALTER PRIMARY KEY USING COLUMNS`, duplicate `ON CONFLICT`). Waiting on [hulykvs PR #5](https://github.com/hcengineering/hulykvs/pull/5). Impact is minimal: kvs only stores sync cursors for Google Calendar and Gmail integrations — all core features work without it.

**huly-v7-next (v3.0.0)** uses **CockroachDB** (`cockroachdb/cockroach:latest-v24.2`), matching the official upstream. CockroachDB speaks the `postgres://` wire protocol — `CR_DB_URL=postgres://user:pass@cockroach:26257/db`. This means all `hardcoreeng/*` services work natively, including `kvs` (which uses CockroachDB-specific `$1` parameterized DDL). MongoDB is also used by `aibot`, `calendar`, and `telegram-bot`.

**huly-v7 (legacy)** uses **PostgreSQL** via `haiodo/*` images from the intabia-fusion fork, which patched services to remove CockroachDB and MongoDB dependencies.

The official [huly-selfhost](https://github.com/hcengineering/huly-selfhost) runs ~14 services on CockroachDB. Our `huly-v7-next`/`huly-v7-pg` runs **40 services** — the extra services (datalake, love, livekit, kvs, calendar, gmail, telegram, love-agent, aibot, rating, hulypulse, stream, media, preview, rekoni, print, github, mail, process-service, link-preview, mongo, cockroach-jobs/pg-jobs) are cloud/enterprise features not included in the official self-hosting guide.

### LiveKit Integration

LiveKit is built into the compose stack as a regular service:

- **Signaling**: Proxied through nginx at `/livekit/` (WebSocket) — browser connects to `wss://huly.example.com/livekit`
- **Internal**: Other services reach LiveKit at `livekit:7880` within the compose network
- **Media ports**: 7881/tcp (RTC), 3478/udp (TURN), 50000-50100/udp (media) exposed directly on the host
- **Redis**: Reuses Huly's existing redis service
- **TURN domain**: Uses `HOST_ADDRESS` (same domain as Huly), with `external_tls: true`
- **API keys**: Auto-generated by Dokploy at deploy time (`livekit_api_key`, `livekit_api_secret`)

The `love` service connects to LiveKit internally (`ws://livekit:7880`). The `front` service tells the browser to connect via `wss://${HOST_ADDRESS}/livekit`. The `love-agent` connects at `ws://livekit:7880`.

### Session Persistence Fix (the key differentiator)

The logout-on-refresh bug happens because Huly V7's account service sets cookies with the wrong domain/flags behind a reverse proxy. Four fixes work together:

1. **`entrypoint.sh`** (inline in template.toml) — runs at nginx startup, strips the first subdomain from `HOST_ADDRESS` to get the parent domain (`huly.example.com` → `.example.com`), then `sed`-replaces placeholders in the nginx template
2. **`proxy_cookie_domain`** — rewrites cookie domain from `.example.com` to `huly.example.com` so cookies are scoped correctly
3. **`proxy_cookie_flags ~ secure samesite=lax`** + **`X-Forwarded-Proto https`** — ensures cookies work over HTTPS (Docker internal traffic is HTTP, so `$scheme` returns "http" without this)
4. **`TRUST_PROXY=true`** on account service — tells the account service to trust reverse proxy headers

### Template Variable Flow

Dokploy auto-generates secrets at deploy time via `template.toml` `[variables]`:

```
main_domain        = "${domain}"        → HOST_ADDRESS, all public URLs
huly_secret        = "${base64:64}"     → SECRET (JWT signing, inter-service auth)
cockroach_password = "${password:32}"   → CR_PASSWORD, CR_DB_URL  (huly-v7-next)
postgres_password  = "${password:32}"   → PG_PASSWORD, PG_DB_URL  (huly-v7-pg) / POSTGRES_PASSWORD (huly-v7 legacy)
redpanda_password  = "${password:16}"   → REDPANDA_ADMIN_PWD
livekit_api_key    = "${password:16}"   → LIVEKIT_API_KEY
livekit_api_secret = "${base64:32}"     → LIVEKIT_API_SECRET
```

These feed into `[config] env` which becomes the `.env` for docker-compose. The `${HULY_VERSION}` variable pins all service image tags (`v0.7.315` for huly-v7, `v0.7.353` for huly-v7-next/huly-v7-pg). The `TEMPLATE_VERSION` env var tracks our template's own semver (separate from upstream Huly).

## Key Configuration

### Required
- `HOST_ADDRESS` — your domain (e.g., `huly.example.com`). Everything derives from this.
- `MAIL_FROM`, `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD` — SMTP config for OTP login emails (or use SES_* vars for Amazon SES)

### Optional
- `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`, `OPENAI_SUMMARY_MODEL`, `OPENAI_TRANSLATE_MODEL` — AI assistant (any OpenAI-compatible provider)
- `STT_PROVIDER` — Speech-to-Text for meeting transcription (love-agent). Provider is `deepgram` (default, key: `DEEPGRAM_API_KEY`, model: nova-3) or `openai` (uses `OPENAI_API_KEY` from AI config, model: gpt-4o-transcribe via Realtime WebSocket API — NOT Whisper).
- `GOOGLE_CREDENTIALS` — Google OAuth credentials JSON for Calendar/Gmail integration
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` — Telegram bot integration (get token from @BotFather)
- `GITHUB_APPID`, `GITHUB_CLIENTID`, `GITHUB_CLIENT_SECRET`, `GITHUB_PRIVATE_KEY`, `GITHUB_BOT_NAME` — GitHub integration
- `PUSH_PUBLIC_KEY`, `PUSH_PRIVATE_KEY`, `PUSH_SUBJECT` — Web Push notifications via VAPID (generate keys with `npx web-push generate-vapid-keys`)
- `SIGN_CERTIFICATE_PASSWORD` — password for the PDF signing PKCS#12 certificate (default: `password` for auto-generated self-signed cert)
- `PLATFORM_ADMIN_EMAILS` — admin user emails
- `TITLE`, `DEFAULT_LANGUAGE`, `LAST_NAME_FIRST` — UI customization

### Auto-Generated (no user config needed)
- `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` — generated by Dokploy at deploy time

### Hardcoded Defaults
- MinIO credentials: `minioadmin`/`minioadmin` (internal only, not exposed)
- CockroachDB/Postgres DB/user: `huly`/`huly`
- Redpanda admin user: `admin`

## Common Tasks

### Versioning

Two independent versions are tracked:

| Version | What it tracks | Where it lives |
|---------|---------------|----------------|
| **Template version** (`v1.1.x` / `v3.1.x` / `v3.2.x`) | Our blueprint/template changes | `meta.json`, `template.toml` `TEMPLATE_VERSION` |
| **Huly version** (`v0.7.315` / `v0.7.353`) | Upstream Docker image tags | `template.toml` `HULY_VERSION`, `coolify/*/.env.example`, `coolify/huly.yaml` defaults, `meta.json` description |

Bump the template version: `./scripts/bump-version.sh [patch|minor|major|next|pg|huly]`

The bump script manages `huly-v7-next` and `huly-v7-pg` (legacy `huly-v7` is left as-is). It updates `meta.json` version badge and `template.toml` `TEMPLATE_VERSION` for the targeted blueprint(s). Use `next`/`pg` to bump a single blueprint, or `patch`/`minor`/`major` to bump both. The version badge shows in Dokploy's template picker UI.

**Important**: Dokploy bakes templates at deploy time. Pushing changes here does NOT update existing deployments. Users should manually edit the compose file and mounts in Dokploy's editor, then click **Redeploy** to preserve data. **Do NOT delete + redeploy** — Dokploy generates a new project name (`-p` flag), which creates new empty volumes and orphans the old data. The `TEMPLATE_VERSION` env var in their Dokploy env panel tells them which version they deployed.

**Dokploy mount behavior**: `[[config.mounts]]` content is written verbatim — `[variables]` are NOT interpolated. Use runtime entrypoint scripts with `sed` replacement (same pattern as nginx and livekit) to inject env var values into config files.

### Update Huly upstream version
Run `./scripts/bump-version.sh huly v0.7.360` — this updates `HULY_VERSION` in both `template.toml` files, both `coolify/*/.env.example` files, the `coolify/huly.yaml` inline defaults, syncs the version into `meta.json` descriptions, and auto-bumps both template patch versions.

### Add/modify a service
1. Add the service in the relevant blueprint's `docker-compose.yml` (e.g., `blueprints/huly-v7-pg/docker-compose.yml`)
2. If it needs a public route, add a `location /_servicename` block in the nginx config inside `template.toml`
3. If it needs new env vars, add them to `[config] env` in `template.toml`

### Add a new nginx route
Edit the nginx config mount in `template.toml` (the second `[[config.mounts]]` block). WebSocket services need `proxy_http_version 1.1` + `Upgrade`/`Connection` headers.

### Test locally
```bash
# From blueprints/huly-v7/
# You'll need to manually create the mounted files since template.toml inline mounts are a Dokploy feature
docker compose up
```
Note: The entrypoint.sh, nginx config, and livekit.yaml are embedded in template.toml as `[[config.mounts]]` — Dokploy writes them to `../files/volumes/` at deploy time. For local testing, you'd need to extract them manually.

## Excluded Services (and why)

These services are excluded from the huly-v7-next and huly-v7-pg blueprints:

| Service | Reason | Impact |
|---------|--------|--------|
| **billing** | Cloud-only feature. Not in official self-hosting. Services gracefully skip when `BillingUrl` is empty. | No usage tracking UI. All features still work. |
| **worker** | Requires Temporal.io infrastructure. Too heavy for self-hosting. | Deferred indefinitely. |

### cockroach-jobs / pg-jobs (meeting-minutes counter reconciliation)

The `cockroach-jobs` (huly-v7-next) / `pg-jobs` (huly-v7-pg) service is a `postgres:17-alpine` sidecar that works around an upstream bug ([PR #10527](https://github.com/hcengineering/platform/pull/10527)) where MeetingMinutes are created via `createDoc` instead of `addCollection`, so the Room's `meetings` collection counter is never incremented. The UI guards on `meetings > 0`, making all meeting minutes invisible even though data is saved correctly.

The sidecar runs a `psql` sleep loop (default every 300s, configurable via `RECONCILE_INTERVAL`) that sets each Room/Office's `meetings` counter to the actual count of MeetingMinutes. It connects to the database via `CR_DB_URL` (huly-v7-next) or `PG_DB_URL` (huly-v7-pg). The reconciliation script is mounted from `template.toml` via the same `[[config.mounts]]` pattern used by nginx and livekit.

**Remove this service once the upstream fix is released in a new Huly version.**

### love-agent token generation

The `love-agent` service uses `hardcoreeng/love-agent` (official image). It requires a `PLATFORM_TOKEN` — a JWT containing the aibot's `personUuid`, signed with `SERVER_SECRET`. The cloud version gets this token from infrastructure; for self-hosting, a custom entrypoint script generates it at startup by logging in as the AI bot (`huly.ai.bot@hc.engineering`) via the accounts service. This follows the same entrypoint pattern used for nginx and livekit configs. If the token generation fails (e.g., accounts service unreachable), the love-agent won't start but video calls still work — only transcription is affected.

## Upstream References

- **Huly (original)**: https://github.com/hcengineering/huly
- **Official self-hosting**: https://github.com/hcengineering/huly-selfhost
- **Docker images** (`hardcoreeng/*`): https://hub.docker.com/u/hardcoreeng
- **Legacy images** (`haiodo/*`): https://hub.docker.com/u/haiodo (dead since Dec 2025)
- **PostgreSQL fork** (legacy): https://github.com/intabia-fusion/foundation-selfhost
- **Huly docs**: https://huly.io/docs/self-hosting
