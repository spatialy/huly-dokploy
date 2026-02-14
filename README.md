# Huly V7 Dokploy Template

---

## Prerequisites: Get Your Server IP and Create Domains

### Step 1: Find Your Server IP

SSH into your server and run:
```bash
curl ifconfig.me
```
This will show your server IP (example: `88.222.521.3`). Write it down - you'll need it.

### Step 2: Create Free Domains

1. Go to https://www.dynu.com/ and create an account
2. Go to **Control Panel**
3. Go to **DDNS Services**
4. Click **Add**

**Create Huly Domain:**
1. Under "Option 1: Use Our Domain Name", enter a name like `huly`
2. Click **Add**
3. Find the **IPv4 Address** field - it will have a random IP
4. Replace it with YOUR server IP (e.g., `88.222.521.3`)
5. Click **Save**

**Create LiveKit Domain:**
1. Click **Add** again
2. Enter a name like `livekit`
3. Click **Add**
4. Replace the **IPv4 Address** with YOUR server IP
5. Click **Save**

Now you have 2 domains:
- `huly.dynu.net` → points to your server
- `livekit.dynu.net` → points to your server

---

## Part 1: Deploy Huly

1. In Dokploy, clikc create project call it somehow like "Huly"  and clikc create.
then clikc create service and select template.
 go to **Templates** and add this repository in the Base url filed. URL "https://raw.githubusercontent.com/shali1995/huly-dokploy-fucking-working/main"
then clikc create.
2. Select the **Huly V7** template
3. Go to **Environment** tab and change:
   ```
   HOST_ADDRESS=huly.dynu.net
   ```
   (Replace with your actual domain)
4. Go to **Domains** tab:
   - Change the domain from the auto-generated one to yours
   - Enable **HTTPS**
5. Click **Deploy**

🎉 **Huly is now running!**

> **Important:** Huly v0.7.331 uses OTP (email code) as the default login method. You **must** configure SMTP for email delivery, otherwise users won't receive login codes. Password login is also available as a fallback (click "Sign in with password" on the login page).

### Configure Email (Required for OTP Login)

In your Huly app's **Environment** tab, set these SMTP variables:

```
MAIL_FROM=noreply@yourdomain.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

**Using Amazon SES instead?** Leave the SMTP fields blank and set:
```
MAIL_FROM=noreply@yourdomain.com
SES_ACCESS_KEY=your-access-key
SES_SECRET_KEY=your-secret-key
SES_REGION=us-east-1
```

Click **Save** and **Redeploy**.

---

## Part 2: Enable Video Calls (Optional)

Video calls require LiveKit. Here's how to set it up:

### Step 1: Deploy LiveKit

1. In Dokploy, create a **new app**
2. Go to **Templates** and search for **LiveKit**
3. Select and create the LiveKit template
4. Go to **Environment** tab, change:
   ```
   LIVEKIT_URL=livekit.dynu.net
   ```
   (Replace with your LiveKit domain)

5. Go to **Domains** tab - you'll see 3 domains
6. Find the one with **Port: 5349**, click edit:
   - Change to `livekit.dynu.net` (your LiveKit domain)
   - Enable **HTTPS**
   - Click **Save**
   
7. Find the one with **Port: 7880**, click edit:
   - Change to `livekit.dynu.net` (your LiveKit domain)
   - Enable **HTTPS**
   - Click **Save**

8. Click **Deploy**

### Step 2: Connect Huly to LiveKit

1. In Dokploy, go to your **LiveKit** app
2. Go to **Environment** tab
3. Find and copy these values:
   ```
   API_KEY=<your_generated_key>
   API_SECRET=<your_generated_secret>
   ```

4. Go back to your **Huly** app
5. Go to **Environment** tab
6. Find these fields and update them:
   ```
   LIVEKIT_HOST=livekit.dynu.net
   LIVEKIT_API_KEY=<paste your API_KEY here>
   LIVEKIT_API_SECRET=<paste your API_SECRET here>
   ```

7. Click **Save** and **Deploy**

🎉 **Video calls are now enabled!**

---

## Important Notes

- ⚠️ You need **2 separate subdomains**: one for Huly, one for LiveKit
- ⚠️ Both domains must point to your server IP
- ⚠️ HTTPS must be enabled on both domains
- ⏳ Wait 1-2 minutes for DNS to propagate before deploying
- 🔄 If something doesn't work, try redeploying

---

## Troubleshooting

### Login doesn't persist after refresh
- Make sure HTTPS is enabled
- Check that HOST_ADDRESS matches your actual domain
- Redeploy the app

### Video calls not working
- Check that both LiveKit domains (ports 5349 and 7880) have HTTPS enabled
- Verify LIVEKIT_HOST, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET are correct
- Make sure your LiveKit domain is different from your Huly domain

### 502 Bad Gateway
- Wait a few seconds and refresh
- If persists, go to Deployments tab and redeploy

---



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
| account | v0.7.331 | Account management |
| transactor | v0.7.331 | Data synchronization |
| collaborator | v0.7.331 | Real-time collaboration |
| front | v0.7.331 | Frontend |
| workspace | v0.7.331 | Workspace management |
| fulltext | v0.7.331 | Full-text search |
| stats | v0.7.331 | Statistics |
| rekoni | v0.7.331 | Document processing |
| datalake | v0.7.331 | Data storage API |
| hulypulse | v0.7.331 | Real-time updates |
| stream | v0.7.331 | Media streaming |
| preview | v0.7.331 | File previews |
| media | v0.7.331 | Media processing |
| love | v0.7.331 | Video calls service |
| love-agent | v0.7.331 | AI voice agent for video calls |
| aibot | v0.7.331 | AI assistant |
| billing | v0.7.331 | Billing service |
| rating | v0.7.331 | Rating service |
| process-service | v0.7.331 | Background processing |
| print | v0.7.331 | Print/export service |
| github | v0.7.331 | GitHub integration |
| mail | v0.7.331 | Email delivery (OTP codes, notifications) |

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

## Optional: GitHub Integration

The GitHub service is included but dormant by default. To enable it:

1. **Create a GitHub App** at https://github.com/settings/apps/new
   - Set the **Webhook URL** to `https://{your-domain}/_github`
   - Grant permissions: Issues (Read & Write), Pull requests (Read & Write), Contents (Read)
   - Subscribe to events: Issues, Pull request, Issue comment
   - Generate a **Private Key** after creation

2. **Set environment variables** in Dokploy:
   ```
   GITHUB_APPID=<your App ID>
   GITHUB_CLIENTID=<your Client ID>
   GITHUB_CLIENT_SECRET=<your Client Secret>
   GITHUB_PRIVATE_KEY=<your Private Key, base64-encoded>
   GITHUB_BOT_NAME=<your App's bot username>
   ```

3. **Redeploy** the template

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

- **Original Huly**: https://github.com/hcengineering/huly
- **PostgreSQL Fork**: https://github.com/intabia-fusion/foundation-selfhost — This template uses the intabia-fusion fork of Huly that replaces CockroachDB with PostgreSQL, making self-hosting simpler and more resource-friendly.
- **Docker Images** (`intabiafusion/*`): https://github.com/intabia-fusion
- **Dokploy Template**: Created to help non-developers deploy Huly without headaches. If it helps you, give it a star!

## License

MIT - Use freely!
