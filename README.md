# Huly V7 Dokploy Template

Complete Dokploy template for Huly V7 with **session persistence fixes** that prevent the logout-on-refresh bug.

## What This Template Fixes

The default Huly V7 deployment has a cookie handling issue that causes users to be logged out when they refresh the page. This template includes all necessary fixes:

1. **Cookie Domain Rewriting** - Automatically configured based on your domain
2. **X-Forwarded-Proto https** - Hardcoded in nginx to fix protocol detection
3. **proxy_cookie_flags** - Sets `Secure` and `SameSite=Lax` on cookies
4. **TRUST_PROXY=true** - Tells the account service to trust reverse proxy headers

## How It Works

The template uses an **entrypoint script** that runs when the nginx container starts:

1. Reads the `HOST_ADDRESS` environment variable (e.g., `huly.example.com`)
2. Calculates the parent domain (e.g., `example.com`)
3. Patches the nginx config with the correct `proxy_cookie_domain` directive
4. Starts nginx with the patched config

This makes the template **zero-config** - you just set your domain and it works!

## Included Services

| Service | Version | Description |
|---------|---------|-------------|
| postgres | 18.1 | Database |
| redis | 8.0 | Cache for hulypulse |
| redpanda | v25.2.11 | Message queue (Kafka compatible) |
| minio | latest | Object storage |
| elastic | 7.14.2 | Search engine |
| nginx | 1.21.3 | Reverse proxy with cookie fixes |
| account | v0.7.315 | Account management |
| transactor | v0.7.315 | Data synchronization |
| collaborator | v0.7.315 | Real-time collaboration |
| front | v0.7.315 | Frontend |
| workspace | v0.7.315 | Workspace management |
| fulltext | v0.7.315 | Full-text search |
| stats | v0.7.315 | Statistics |
| rekoni | v0.7.315 | Document processing |
| datalake | v0.7.315 | Data storage API |
| hulypulse | v0.7.315 | Real-time updates |
| stream | v0.7.315 | Media streaming |
| preview | v0.7.315 | File previews |
| media | v0.7.315 | Media processing |
| love | v0.7.315 | Video calls service |
| aibot | v0.7.315 | AI assistant |
| billing | v0.7.315 | Billing service |
| rating | v0.7.315 | Rating service |
| process-service | v0.7.315 | Background processing |

## Usage

### In Dokploy

1. Go to **Templates** in Dokploy
2. Import this template
3. Set your domain (e.g., `huly.yourdomain.com`)
4. Deploy!

### Manual Testing

If you want to test manually:

1. Copy `docker-compose.yml` and `template.toml` to your Dokploy templates folder
2. Deploy via Dokploy

## Configuration

The template auto-generates these values:

| Variable | Type | Description |
|----------|------|-------------|
| `main_domain` | domain | Your Huly domain (e.g., huly.example.com) |
| `huly_secret` | base64:64 | Secret for JWT tokens |
| `postgres_password` | password:32 | PostgreSQL password |
| `redpanda_password` | password:16 | Redpanda admin password |

## Optional: LiveKit (Video Calls)

This template does NOT include LiveKit because:
- LiveKit requires host networking or specific port forwarding
- It needs separate SSL certificates
- It's complex to configure in a Docker template

For video calls, you would need to:
1. Deploy LiveKit separately
2. Set `LIVEKIT_HOST`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` in the love service
3. Configure firewall rules for ports 7880, 7881, 5349, 3478, 50000-60000

## Troubleshooting

### Login loop / Logged out on refresh

If you're still being logged out on refresh:

1. Check the nginx entrypoint logs:
   ```
   docker logs <nginx-container> | head -20
   ```
   You should see the parent domain being calculated

2. Verify the cookie domain in browser dev tools:
   - Open F12 → Application → Cookies
   - Check that cookies have the correct domain

### Database connection errors

Postgres needs time to initialize. The template includes health checks, but if you see connection errors, wait 30 seconds and redeploy.

### Services not starting

Check that all services are on the same Docker network. Dokploy should handle this automatically.

## Credits

- Original Huly: https://github.com/hcengineering/huly
- V7 Cookie Fix Research: 4 days of debugging session persistence issues
- Template Author: Created to help Dokploy users avoid the session logout bug

## License

MIT - Use freely!
