# Changelog

All notable changes to this project are documented here. This project maintains two independent blueprints (`huly-v7` and `huly-v7-next`) with separate version tracks.

## huly-v7-next

### v3.0.5 (2026-02-18)
- **fix**: Switch love-agent from `haiodo/love-agent:v0.7.315` to official `hardcoreeng/love-agent`. The haiodo fork's JWT used a hardcoded `systemAccountUuid` that didn't match the aibot's `personUuid`, causing 401 on the identity endpoint. New entrypoint script generates `PLATFORM_TOKEN` at startup by logging in as the AI bot via the accounts service.
- **change**: STT env vars now follow hardcoreeng naming — `DEEPGRAM_API_KEY` replaces `STT_API_KEY`, default provider changed from `stream` to `deepgram`.

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
