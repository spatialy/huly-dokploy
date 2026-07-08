# Changelog

All notable changes to this project are documented here. This project maintains three blueprints (`huly-v7`, `huly-v7-next`, `huly-v7-pg`) with separate version tracks.

## huly-v7-pg

### v3.4.0 (2026-07-08)

Upstream sync: Huly **v0.7.382 → v0.7.426** (PG variant only — matches the version pinned by the official [huly-selfhost](https://github.com/hcengineering/huly-selfhost) as of July 2026). All 31 `hardcoreeng/*` images verified to publish the `v0.7.426` tag on Docker Hub.

- **change**: Bump `HULY_VERSION` to v0.7.426 in `template.toml` and `coolify/huly-v7-pg/.env.example`.
- **add**: `DISABLED_FEATURES=auto-translate,mailboxes` on the `front` service — mirrors the official self-host compose, which disables these cloud-only UI features. Overridable via env.
- **add**: `HULY_BACKEND=redis` on `hulypulse` — upstream's newer hulypulse defaults to an in-memory backend unless told to use Redis; the existing `HULY_REDIS_URLS`/`HULY_REDIS_MODE` vars are kept.
- **kept**: `pg-jobs` reconciliation sidecar — upstream [PR #10527](https://github.com/hcengineering/platform/pull/10527) (meeting-minutes counter fix) is still open as of this release, so the workaround remains necessary.
- **kept**: `DESKTOP_UPDATES_CHANNEL=selfhost` — upstream now sets the channel to the version number (`0.7.426`); not adopted, pending clarity on the channel semantics for desktop clients.
- **note**: nginx route audit against the official `.huly.nginx` found no new public routes; ours remain a superset.
- **note**: the blueprints now track different upstream versions (pg: v0.7.426, next: v0.7.382). `bump-version.sh huly` updates both to the same version — bump a single blueprint manually while they stay diverged.

### v3.3.0 (2026-07-07)

Security & deployment hardening pass (PG variant only — huly-v7-next unchanged).

- **security**: AI bot account password is no longer the hardcoded `password`. New auto-generated `AI_BOT_PASSWORD` template variable, wired to the aibot service and the love-agent token-generation entrypoint. The bot account (`huly.ai.bot@hc.engineering`) is reachable via the public `/_accounts` login endpoint, so a well-known password allowed anyone to authenticate as the bot. Compose falls back to `password` when the env var is unset (backward compatible with existing deployments — see note below).
- **security**: MinIO credentials are no longer `minioadmin`/`minioadmin`. Dokploy auto-generates `S3_ACCESS_KEY`/`S3_SECRET_KEY` at deploy time; the Coolify `.env.example` now instructs generating them before first deploy. Compose keeps `minioadmin` fallbacks for existing deployments.
- **security**: `SIGN_CERTIFICATE_PASSWORD` is auto-generated instead of defaulting to `password`.
- **security**: nginx per-IP rate limit on `/_accounts` (20 r/s, burst 40) to mitigate login/OTP brute force, plus security headers (`Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`).
- **security**: Image updates — `nginx:1.21.3` → `nginx:1.28-alpine` (2021-era image with known CVEs), `elasticsearch:7.14.2` → `7.17.28` (EOL, pre-Log4Shell), and pinned previously floating tags: `livekit/livekit-server:latest` → `v1.13.3`, `minio/minio` → `RELEASE.2025-09-07T16-13-09Z`.
- **add**: Log rotation on all 40 services (`json-file`, 10 MB × 3 files) — prevents unbounded container logs from filling the disk. `STREAM_LOG_LEVEL` now defaults to `info` (was `debug`), overridable via env.
- **add**: Memory limits on datastores (postgres 1G, elastic 2G, redpanda 2G, mongo 768M) so a memory spike is contained instead of OOM-killing arbitrary containers.
- **add**: Healthchecks on `account`, `transactor`, and `front` (TCP connect via node). `datalake`, `aibot`, and `process-service` now wait for `account` to be healthy instead of merely started — fewer crash-loops on cold start.

**Note for existing deployments**: the AI bot account was already created with password `password`. Setting `AI_BOT_PASSWORD` on an existing deployment does not change the stored password (and would break the love-agent login). Either keep the fallback, or reset the bot account password in the database to the new value.

### v3.2.8 (2026-04-02)
- **fix**: Fix backup crash-loop — revert backup/backup-api from `s3|` to `minio|` storage kind. The `s3|` kind (introduced in v3.2.4) uses AWS SDK v3 which defaults to virtual-hosted-style S3 addressing, constructing unresolvable hostnames like `backups.minio` and `<workspace-uuid>.minio`. The `minio|` kind uses minio-js which always uses path-style addressing, matching the official huly-selfhost config. Telegram-bot still uses `s3|` (not actively failing).

### v3.2.7 (2026-03-05)
- **change**: Bump Huly upstream to v0.7.382. Card/process automation, invite settings, PostgreSQL `IN ()` syntax fix.
- **change**: Remove `STATS_VERSION` env var — stats image now uses `v`-prefix tags again (same as `HULY_VERSION`). Upstream resumed publishing `v`-prefix for `hardcoreeng/stats` as of v0.7.382.

### v3.2.4 (2026-02-23)
- **add**: External S3 storage support. New env vars `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_REGION` default to bundled MinIO but can be overridden for AWS S3, Backblaze B2, Cloudflare R2, or any S3-compatible provider. Zero-config for existing users.
- **change**: Standardize on `s3|` adapter prefix (replacing `minio|` on backup, backup-api, telegram-bot). Love already used `s3|` with MinIO.
- **change**: Love service `STORAGE_PROVIDER_NAME` changed from `minio` to `s3`.
- **change**: MinIO container credentials now wired via `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` from `S3_ACCESS_KEY`/`S3_SECRET_KEY`.

### v3.2.6 (2026-02-24)
- **fix**: Add inline defaults for S3 env vars (`S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_REGION`) and `STORAGE_CONFIG` in docker-compose.yml. Fixes datalake crash-loop (`TypeError: Invalid URL` on `?accessKey=&secretKey=&region=`) when deploying via Dokploy Git provider, which doesn't process template.toml `[config] env` defaults. Also fixes collaborator `fetch failed` errors (couldn't reach crashed datalake).

### v3.2.5 (2026-02-23)
- **fix**: Replace `INIT_WORKSPACE=none` with `INIT_REPO_DIR=/nonexistent` — the previous approach didn't fully work because the upstream `initializeWorkspace()` falls through to the default "huly" init script when no script name matches. The new approach points the init scripts directory to a non-existent path, causing `initializeWorkspace()` to skip entirely. New workspaces are now truly empty (no demo projects, Card types, or sample content). Set `INIT_REPO_DIR=./init-scripts` to restore demo content.

### v3.2.1 (2026-02-22)
- **change**: Bump Huly upstream to v0.7.375.
- **fix**: KVS now natively supports PostgreSQL — removed `CREATE DOMAIN bytes AS bytea;` init script workaround. [hulykvs PR #5](https://github.com/hcengineering/hulykvs/pull/5) merged upstream and shipped in v0.7.375. Google Calendar and Gmail sync state now works on PostgreSQL.
- **fix**: Stats image uses `STATS_VERSION` with `s`-prefix tags (`s0.7.375`). Upstream stopped publishing `v`-prefix tags for `hardcoreeng/stats` after v0.7.353.

### v3.2.0 (2026-02-20)
- **add**: New PostgreSQL blueprint variant — same 40 services as `huly-v7-next` but replaces CockroachDB with PostgreSQL 17 (`postgres:17-alpine`). Saves ~1-1.5GB RAM at idle.
- **add**: KVS DDL compatibility via `CREATE DOMAIN bytes AS bytea;` in PostgreSQL init script.
- **known issue**: KVS (hulykvs) crash-loops on PostgreSQL due to additional CockroachDB-specific SQL beyond the DDL (`SET search_path TO $1`, `ALTER PRIMARY KEY USING COLUMNS`, duplicate `ON CONFLICT` columns). Only affects Google Calendar and Gmail integration sync state — all core features work. Waiting on [hulykvs PR #5](https://github.com/hcengineering/hulykvs/pull/5) for upstream fix.
- **add**: Account service flag `PROCEED_V7_MONGO=false` to skip MongoDB migration path.
- **add**: `pg-jobs` sidecar (same meeting-minutes counter reconciliation as `cockroach-jobs`, using `PG_DB_URL`).
- **add**: Coolify / Docker Compose variant at `coolify/huly-v7-pg/` with `.env.example` and extracted config files.
- Env vars renamed: `CR_DATABASE/CR_USERNAME/CR_PASSWORD/CR_DB_URL` → `PG_DATABASE/PG_USERNAME/PG_PASSWORD/PG_DB_URL`.
- Based on upstream PostgreSQL support (PR #10331, Dec 2025) included in v0.7.353.

## huly-v7-next

### v3.1.8 (2026-04-02)
- **fix**: Fix backup crash-loop — revert backup/backup-api from `s3|` to `minio|` storage kind. Same fix as huly-v7-pg v3.2.8.

### v3.1.7 (2026-03-05)
- **change**: Bump Huly upstream to v0.7.382. Card/process automation, invite settings, PostgreSQL `IN ()` syntax fix.
- **change**: Remove `STATS_VERSION` env var — stats image now uses `v`-prefix tags again (same as `HULY_VERSION`). Upstream resumed publishing `v`-prefix for `hardcoreeng/stats` as of v0.7.382.

### v3.1.4 (2026-02-23)
- **add**: External S3 storage support. New env vars `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_REGION` default to bundled MinIO but can be overridden for AWS S3, Backblaze B2, Cloudflare R2, or any S3-compatible provider. Zero-config for existing users.
- **change**: Standardize on `s3|` adapter prefix (replacing `minio|` on backup, backup-api, telegram-bot). Love already used `s3|` with MinIO.
- **change**: Love service `STORAGE_PROVIDER_NAME` changed from `minio` to `s3`.
- **change**: MinIO container credentials now wired via `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` from `S3_ACCESS_KEY`/`S3_SECRET_KEY`.

### v3.1.6 (2026-02-24)
- **fix**: Add inline defaults for S3 env vars and `STORAGE_CONFIG` in docker-compose.yml. Fixes datalake crash-loop when deploying via Dokploy Git provider (same fix as huly-v7-pg v3.2.6).

### v3.1.5 (2026-02-23)
- **fix**: Replace `INIT_WORKSPACE=none` with `INIT_REPO_DIR=/nonexistent` — the previous approach didn't fully work because the upstream `initializeWorkspace()` falls through to the default "huly" init script when no script name matches. The new approach points the init scripts directory to a non-existent path, causing `initializeWorkspace()` to skip entirely. New workspaces are now truly empty (no demo projects, Card types, or sample content). Set `INIT_REPO_DIR=./init-scripts` to restore demo content.

### v3.1.1 (2026-02-22)
- **change**: Bump Huly upstream to v0.7.375.
- **fix**: Stats image uses `STATS_VERSION` with `s`-prefix tags (`s0.7.375`). Upstream stopped publishing `v`-prefix tags for `hardcoreeng/stats` after v0.7.353.

### v3.1.0 (2026-02-19)
- **add**: Coolify and Docker Compose support — two new deployment methods alongside existing Dokploy blueprints:
  - `coolify/huly-v7-next/` — Standard Docker Compose directory with real config files. Works with Coolify (Git repo), Portainer, Dockge, or bare `docker compose up`. Includes `.env.example` with documented variables and secret generation commands.
  - `coolify/huly.yaml` — Single-file Coolify service template with `SERVICE_*` magic variables for auto-generated secrets and `content:` directives for inline config files. Ready for future PR to `coollabsio/coolify`.
- Config files extracted from `template.toml` inline mounts into standalone files under `coolify/huly-v7-next/volumes/` (nginx, livekit, love-agent, cockroach-jobs).
- Dokploy files unchanged — all deployment methods coexist.
- **add**: Backup service (`hardcoreeng/backup`) — automatic hourly workspace backups to MinIO. Enabled by default, 84 snapshots retained.
- **add**: Backup API (`hardcoreeng/backup-api`) — backup download endpoint at `/_backup/`.
- **add**: Export service (`hardcoreeng/export`) — workspace data export as ZIP at `/_export/`.
- **add**: Notification service (`hardcoreeng/notification`) — Web Push notifications via VAPID. Optional (needs user-generated keys via `npx web-push generate-vapid-keys`).
- **add**: Sign service (`hardcoreeng/sign`) — PDF digital signatures. Auto-generates self-signed PKCS#12 cert on first start; replaceable with AATL cert for production.
- Total services: 35 → 40.

### v3.0.9 (2026-02-18)
- **fix**: Telegram-bot using wrong image (`hardcoreeng/telegram` instead of broken MTProto `telegram` image).

### v3.0.8 (2026-02-18)
- **add**: Meeting-minutes counter reconciliation sidecar (`cockroach-jobs`). Workaround for upstream bug ([PR #10527](https://github.com/hcengineering/platform/pull/10527)) where MeetingMinutes are created via `createDoc` instead of `addCollection`, so the Room's `meetings` counter is never incremented and the UI shows "No meeting minutes". A `postgres:17-alpine` sidecar runs `psql` every 5 minutes (configurable via `RECONCILE_INTERVAL`) to set each Room's counter to the actual MeetingMinutes count. Will be removed once the upstream fix is released.

### v3.0.7 (2026-02-18)
- **fix**: Love-agent crash loop — wrong entry point. Was running `node agent.js` which just exports the module and exits silently. Correct command is `node index.js start` (LiveKit Agent SDK CLI requires the `start` argument to enter worker mode).
- **docs**: Consolidate README — merge duplicate sections, rewrite STT docs for hardcoreeng love-agent (Deepgram/OpenAI Realtime API), fix love-agent version in service table, add huly-v7-next to file structure, wrap service tables in collapsible `<details>`.

### v3.0.6 (2026-02-18)
- **fix**: Love-agent entrypoint token generation failing. Two bugs: (1) `login` RPC was sending params as array `['email', 'password']` but v0.7.353 accounts service expects object `{ email, password }` — caused `BadRequest`. (2) `loginOrSignUp` method doesn't exist in v0.7.353 — caused `UnknownMethod`. Added robust fallback: if `login` fails, generates a system JWT (HS256, signed with `SERVER_SECRET`) using the hardcoded `systemAccountUuid`, queries the accounts service for the ai-bot's `PersonUUID` via `findPersonBySocialKey`, then mints `PLATFORM_TOKEN` directly.

### v3.0.5 (2026-02-18)
- **fix**: Switch love-agent from `haiodo/love-agent:v0.7.315` to official `hardcoreeng/love-agent`. The haiodo fork's JWT used a hardcoded `systemAccountUuid` that didn't match the aibot's `personUuid`, causing 401 on the identity endpoint. New entrypoint script generates `PLATFORM_TOKEN` at startup by logging in as the AI bot via the accounts service.
- **change**: STT env vars updated for hardcoreeng love-agent. Old `STT_URL`/`STT_API_KEY`/`STT_MODEL` removed. New vars: `STT_PROVIDER` (`deepgram` or `openai`), `DEEPGRAM_API_KEY`, or `OPENAI_API_KEY`. OpenAI uses the Realtime WebSocket API (`gpt-4o-transcribe`), not Whisper — `whisper-1` is not supported.

### v3.0.4 (2026-02-18)
- **fix**: LiveKit meetings returning 404. Variable-based `proxy_pass $upstream_livekit` doesn't strip the `/livekit/` prefix like static `proxy_pass` does. Added missing `rewrite ^/livekit(/.*)$ $1 break;` rule (matching the pattern used by all other location blocks).

### v3.0.3 (2026-02-17)
- **fix**: Remove dead env vars (`NOTIFICATION_URL`, `BRANDING_URL`) that referenced non-existent services.
- **docs**: Document signup behavior — first user gets owner role automatically.

### v3.0.2 (2026-02-17)
- **fix**: Accounts rewrite producing zero-length URI. Split into two rules: `rewrite ^/_accounts$ / break` and `rewrite ^/_accounts(/.*)$ $1 break`.

### v3.0.1 (2026-02-17)
- **fix**: Signup returning 404. The nginx rewrite for `/_accounts` required a trailing path but the signup POST hits `/_accounts` with no trailing path.

### v3.0.0 (2026-02-16)
- **breaking**: Migrate from PostgreSQL to CockroachDB (`cockroachdb/cockroach:latest-v24.2`), matching the official upstream architecture. Existing PostgreSQL data is not compatible.
- **add**: Full service stack — `kvs`, `calendar`, `gmail`, `telegram-bot`, `link-preview`, `aibot` + MongoDB, `love-agent`, `rating`, `hulypulse`, `stream`, `media`, `preview`, `process-service`. Total: 34 services.
- **add**: Google Calendar/Gmail integration (via `GOOGLE_CREDENTIALS`), Telegram bot (via `TELEGRAM_BOT_TOKEN`).
- **change**: All images now use `hardcoreeng/*` (official upstream) instead of `haiodo/*` (dead fork).

### v2.x (2026-02-15)
- Initial `huly-v7-next` blueprint using `hardcoreeng/*` images on PostgreSQL.
- Added aibot + MongoDB service.
- Made nginx resilient to optional services with variable-based upstreams.

## huly-v7 (legacy)

### v1.1.x
- Uses `haiodo/*` images at v0.7.315 from the intabia-fusion PostgreSQL fork.
- 29 services including billing, love-agent (both work natively on haiodo).

### v1.1.0
- Added semantic versioning with `scripts/bump-version.sh`.
- Merged LiveKit into single compose blueprint (was separate deployment).
- Fixed LiveKit auth by using runtime `sed` replacement instead of Dokploy variable interpolation (Dokploy does not interpolate `[[config.mounts]]` content).
- Fixed LiveKit entrypoint to use absolute path `/livekit-server`.

### v1.0.x (pre-versioning)
- Initial fork from `shali1995/huly-dokploy-fucking-working`.
- Core session persistence fix (proxy_cookie_domain + proxy_cookie_flags + X-Forwarded-Proto + TRUST_PROXY).
- Upgraded to intabia-fusion v0.7.331.
- Added services: print, github, love-agent, mail, aibot.
- Added SMTP/SES email configuration for OTP login.
- Added AI assistant (OpenAI) configuration.
- Added GitHub integration support.
- Added STT configuration for meeting transcription.

## Docs

### 2026-02-22
- **docs**: Add "Deploy from Git Repository" option to Dokploy section in README. Documents how to deploy via Dokploy's Git source (using `coolify/huly-v7-pg/` directory), with step-by-step instructions, volume safety notes, and upgrade workflow. Git deploys use a stable project name, avoiding the volume orphaning risk of template-based Delete + Redeploy.
- **docs**: Add "Disable Sign-Up" security note to Important Notes section. Explains that Huly instances are open to public registration by default and how to set `DISABLE_SIGNUP=true` after creating the first user.
- **add**: Wire `DISABLE_SIGNUP` env var to `account` and `front` services in all blueprints, Coolify compose files, template.toml files, and `.env.example` files. Defaults to `false`.

## Research

### 2026-02-21
- **add**: `improvements-aibot-tooling.md` — research document analyzing approaches to inject custom tools into Huly's AI assistant (`hardcoreeng/ai-bot`) without upstream changes. Covers current architecture, Huly API surface (`@hcengineering/api-client`, `@firfi/huly-mcp`), 4 injection patterns (Smart Context Proxy, Tool Loop Interceptor, MCP Sidecar, Custom Image), recommended phased evolution path, tool catalog, and implementation roadmap.
- **add**: `research-huly-ai-agent.md` — comprehensive analysis of the newer `hcengineering/huly-ai-agent` repository (Rust, 330K LoC). Covers architecture, 25+ tools, native MCP support, memory system, scheduler, comparison with `pod-ai-bot`, and self-hosting feasibility. Key finding: all core dependencies (`hulyrs`, `mcp-core`) are public — source is fully buildable.

## Tooling

### 2026-02-22
- **change**: `bump-version.sh huly` now also updates `STATS_VERSION` (s-prefix) across all files. Stats image stopped getting v-prefix tags upstream after v0.7.353.

### 2026-02-20
- **change**: Rewrite `scripts/bump-version.sh` to manage `huly-v7-next` and `huly-v7-pg` (legacy `huly-v7` left as-is). New subcommands: `next`, `pg`, `patch`/`minor`/`major`, `huly`, `status`.
- **change**: `huly` subcommand now updates 6 files: both `template.toml`, both Coolify `.env.example`, `coolify/huly.yaml` inline defaults, and `meta.json`.
- **change**: Rewrite `scripts/pre-commit` hook to detect which blueprint(s) changed and bump only those.
- **remove**: Root `VERSION` file — each blueprint's version now lives in its own `template.toml`.
