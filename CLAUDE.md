# CLAUDE.md - Huly V7 Dokploy Template

## Project Overview

Dokploy blueprint templates for self-hosting [Huly V7](https://huly.io/) — an all-in-one project management platform. The template's core value is a **session persistence fix** that prevents the logout-on-refresh bug in Huly V7 behind reverse proxies.

Forked from `shali1995/huly-dokploy-fucking-working`. Huly Docker images use `haiodo/*` from the [intabia-fusion/foundation-selfhost](https://github.com/intabia-fusion/foundation-selfhost) PostgreSQL fork (replaces CockroachDB). The `intabiafusion/*` images exist but aren't production-ready yet — we track `haiodo/*` to match their actual upstream compose.

## Repository Structure

```
meta.json                              # Blueprint registry: two entries (huly-v7, livekit)
README.md                              # User-facing deployment guide
blueprints/huly-v7/
  template.toml                        # Dokploy template: variables, env, domains, mounted files
  docker-compose.yml                   # 28 services orchestration
  huly.svg                             # Logo for Dokploy UI
blueprints/livekit/
  template.toml                        # LiveKit template: variables, env, domains, config mount
  docker-compose.yml                   # LiveKit server + Redis
  livekit.svg                          # Logo for Dokploy UI
```

`template.toml` is the single source of truth for each blueprint — it contains the nginx config and entrypoint script (huly-v7) or livekit.yaml (livekit) as inline `[[config.mounts]]` entries.

## Architecture

### Multi-Blueprint Design

Two separate Dokploy blueprints communicate via a **named Docker network** (`huly_net`):

- **huly-v7**: Main Huly stack. Creates `huly_net` (non-external, `name: huly_net`).
- **livekit**: LiveKit WebRTC server. Joins `huly_net` as external with alias `livekit`.

Deployment order: **Huly first** (creates `huly_net`), then **LiveKit** (joins it).

### Network Architecture

```
                  huly_net (named Docker bridge)
                  ┌──────────────────────────────┐
                  │                              │
  ┌───────────────┴──────────────┐  ┌────────────┴──────────┐
  │  Huly Stack (huly-v7)        │  │  LiveKit Stack         │
  │                              │  │                        │
  │  nginx → all services        │  │  livekit (alias on     │
  │  postgres, redis, redpanda   │  │    huly_net: "livekit")│
  │  minio, elastic              │  │  redis (internal)      │
  │  love-agent → livekit:7880   │  │                        │
  └──────────────────────────────┘  └────────────────────────┘
```

### Service Layers

All traffic enters through **nginx:80**, which routes by URL path prefix:

| Layer | Services |
|-------|----------|
| **Proxy** | nginx (routes `/_<name>` paths to backends) |
| **Infrastructure** | postgres:18.1, redis:8.0, redpanda:v25.2.11 (Kafka), minio (S3), elastic:7.14.2 |
| **Core** | account:3000, transactor:3333, front:8080, workspace, collaborator:3078, fulltext:4700 |
| **Feature** | love:8097 (video), love-agent, aibot:4011, billing:4042, stats:4900, hulypulse:8098, stream:1081, media, preview:4043, datalake:4031, rekoni:4004, print:4005, github:3500, mail:8097, rating, process-service |

### Session Persistence Fix (the key differentiator)

The logout-on-refresh bug happens because Huly V7's account service sets cookies with the wrong domain/flags behind a reverse proxy. Four fixes work together:

1. **`entrypoint.sh`** (inline in template.toml) — runs at nginx startup, strips the first subdomain from `HOST_ADDRESS` to get the parent domain (`huly.example.com` → `.example.com`), then `sed`-replaces placeholders in the nginx template
2. **`proxy_cookie_domain`** — rewrites cookie domain from `.example.com` to `huly.example.com` so cookies are scoped correctly
3. **`proxy_cookie_flags ~ secure samesite=lax`** + **`X-Forwarded-Proto https`** — ensures cookies work over HTTPS (Docker internal traffic is HTTP, so `$scheme` returns "http" without this)
4. **`TRUST_PROXY=true`** on account service — tells the account service to trust reverse proxy headers

### Template Variable Flow

Dokploy auto-generates secrets at deploy time via `template.toml` `[variables]`:

**Huly (huly-v7):**
```
main_domain   = "${domain}"        → HOST_ADDRESS, all public URLs
huly_secret   = "${base64:64}"     → SECRET (JWT signing, inter-service auth)
postgres_password = "${password:32}" → POSTGRES_PASSWORD, CR_DB_URL
redpanda_password = "${password:16}" → REDPANDA_ADMIN_PWD
```

**LiveKit:**
```
livekit_domain    = "${domain}"       → LIVEKIT_DOMAIN
livekit_api_key   = "${password:16}"  → LIVEKIT_API_KEY
livekit_api_secret = "${base64:32}"   → LIVEKIT_API_SECRET
```

These feed into `[config] env` which becomes the `.env` for docker-compose. The `${HULY_VERSION}` variable (currently `v0.7.315`) pins all `haiodo/*` image tags.

## Key Configuration

### Required
- `HOST_ADDRESS` — your domain (e.g., `huly.example.com`). Everything derives from this.
- `MAIL_FROM`, `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD` — SMTP config for OTP login emails (or use SES_* vars for Amazon SES)

### Optional
- `LIVEKIT_HOST`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` — video calls (LiveKit deployed as separate blueprint)
- `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`, `OPENAI_SUMMARY_MODEL`, `OPENAI_TRANSLATE_MODEL` — AI assistant (any OpenAI-compatible provider)
- `STT_PROVIDER`, `STT_URL`, `STT_API_KEY`, `STT_MODEL` — Speech-to-Text for AI voice features
- `GITHUB_APPID`, `GITHUB_CLIENTID`, `GITHUB_CLIENT_SECRET`, `GITHUB_PRIVATE_KEY`, `GITHUB_BOT_NAME` — GitHub integration
- `PLATFORM_ADMIN_EMAILS` — admin user emails
- `TITLE`, `DEFAULT_LANGUAGE`, `LAST_NAME_FIRST` — UI customization

### Hardcoded Defaults
- MinIO credentials: `minioadmin`/`minioadmin` (internal only, not exposed)
- Postgres DB/user: `huly`/`huly`
- Redpanda admin user: `admin`

## Common Tasks

### Update Huly version
Change `HULY_VERSION=v0.7.315` in `template.toml` line 9 and `meta.json` version field. All 21 `haiodo/*` services use this single variable.

### Add/modify a service
1. Add the service in `blueprints/huly-v7/docker-compose.yml`
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
Note: The entrypoint.sh and nginx config are embedded in template.toml as `[[config.mounts]]` — Dokploy writes them to `../files/volumes/nginx/` at deploy time. For local testing, you'd need to extract them manually.

## Excluded Services (and why)

| Service | Reason |
|---------|--------|
| Calendar | Requires MongoDB + KVS (new infrastructure). Deferred to future. |
| Gmail/Telegram | Advanced integrations requiring external credentials. Future phase. |

## Upstream References

- **Huly (original)**: https://github.com/hcengineering/huly
- **PostgreSQL fork**: https://github.com/intabia-fusion/foundation-selfhost
- **Docker images** (`haiodo/*`): https://hub.docker.com/u/haiodo
- **Huly docs**: https://huly.io/docs/self-hosting
