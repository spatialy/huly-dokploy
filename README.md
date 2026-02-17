# Huly V7 Dokploy Template

---

## Prerequisites: Get Your Server IP and Create a Domain

### Step 1: Find Your Server IP

SSH into your server and run:
```bash
curl ifconfig.me
```
This will show your server IP (example: `88.222.521.3`). Write it down - you'll need it.

### Step 2: Create a Free Domain

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

Now you have a domain:
- `huly.dynu.net` -> points to your server

---

## Deploy Huly

1. In Dokploy, click create project, call it something like "Huly", and click create.
Then click create service and select template.
Go to **Templates** and add this repository in the Base URL field. URL: `https://raw.githubusercontent.com/spatialy/huly-dokploy/main`
Then click create.
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

**Huly is now running!** Video calls (LiveKit) are built-in and work automatically -- API keys are auto-generated at deploy time.

> **Important:** Huly v0.7.315 uses OTP (email code) as the default login method. You **must** configure SMTP for email delivery, otherwise users won't receive login codes. Password login is also available as a fallback (click "Sign in with password" on the login page).

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

<details>
<summary><strong>AWS SES Setup Guide (IAM + SES Console)</strong></summary>

#### 1. Verify your sender identity in SES

1. Go to **Amazon SES** > **Identities** > **Create identity**
2. Choose **Email address** (quick) or **Domain** (production)
   - For email: enter the address you'll use as `MAIL_FROM`, click the verification link
   - For domain: add the DKIM CNAME records SES gives you to your DNS
3. If your SES account is in **sandbox mode** (default for new accounts), you can only send to verified email addresses. To send to anyone, request **production access**: SES > **Account dashboard** > **Request production access**

#### 2. Create an IAM user for SES

1. Go to **IAM** > **Users** > **Create user**
2. Name it something like `huly-ses-sender`
3. Select **Attach policies directly**
4. Click **Create policy** and use this JSON:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ses:SendEmail",
           "ses:SendRawEmail"
         ],
         "Resource": "*"
       }
     ]
   }
   ```
   Name it `HulySESSendEmail` and attach it to the user
5. Go to the user > **Security credentials** > **Create access key**
6. Select **Application running outside AWS**
7. Copy the **Access key ID** -> `SES_ACCESS_KEY` and **Secret access key** -> `SES_SECRET_KEY`

#### 3. Set the Huly env vars

```
MAIL_FROM=noreply@yourdomain.com   # Must match a verified SES identity
SES_ACCESS_KEY=AKIA...             # From step 2
SES_SECRET_KEY=...                 # From step 2
SES_REGION=us-east-1               # The region where you verified your identity
```

</details>

Click **Save** and **Redeploy**.

---

## Firewall Requirements (for Video Calls)

LiveKit is built into the Huly stack. WebSocket signaling goes through nginx on the same domain (`wss://huly.example.com/livekit`), but media/TURN traffic requires these ports to be open on your server's firewall:

| Port | Protocol | Purpose |
|------|----------|---------|
| 7881 | TCP | LiveKit RTC (WebRTC over TCP) |
| 3478 | UDP | TURN server |
| 50000-50100 | UDP | Media (WebRTC audio/video) |

If you're using a cloud provider (AWS, Hetzner, DigitalOcean, etc.), make sure these ports are allowed in your security group / firewall rules.

---

## Important Notes

- You need only **1 domain** -- LiveKit is built-in and shares the same domain
- HTTPS must be enabled on your domain
- Wait 1-2 minutes for DNS to propagate before deploying
- If something doesn't work, try redeploying

### Template Versioning

This template tracks **two independent versions**:

| Version | What | Example |
|---------|------|---------|
| **Template version** | Our blueprint changes (fixes, config improvements) | `v1.1.0` (shown as badge in Dokploy template picker) |
| **Huly version** | Upstream `haiodo/*` Docker image tags | `v0.7.315` (shown in description) |

**Dokploy bakes templates at deploy time.** Pushing updates to this repo does NOT update existing deployments. To check which version you deployed, look for `TEMPLATE_VERSION` in your Dokploy **Environment** tab.

**To upgrade without losing data:** Edit the docker-compose.yml and mounted files directly in Dokploy's compose editor, then click **Redeploy**. This preserves all Docker volumes (database, files, etc.).

> **Warning:** Do NOT delete and redeploy from the template to upgrade. Dokploy generates a new project name on each deploy, which creates new empty volumes. Your old data becomes orphaned (still on disk, but not attached to the new deployment).

---

## Troubleshooting

### Login doesn't persist after refresh
- Make sure HTTPS is enabled
- Check that HOST_ADDRESS matches your actual domain
- Redeploy the app

### Video calls not working
- Check that ports 7881/tcp, 3478/udp, and 50000-50100/udp are open on your server firewall
- Verify `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are set in the environment (auto-generated at deploy time)
- Try redeploying

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
| redis | 8.0 | Cache for hulypulse and LiveKit |
| redpanda | v25.2.11 | Message queue (Kafka compatible) |
| minio | latest | Object storage |
| elastic | 7.14.2 | Search engine |
| nginx | 1.21.3 | Reverse proxy with cookie fixes |
| livekit | latest | WebRTC server for video calls |
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
| love-agent | v0.7.315 | AI voice agent for video calls |
| aibot | v0.7.315 | AI assistant |
| billing | v0.7.315 | Billing service |
| rating | v0.7.315 | Rating service |
| process-service | v0.7.315 | Background processing |
| print | v0.7.315 | Print/export service |
| github | v0.7.315 | GitHub integration |
| mail | v0.7.315 | Email delivery (OTP codes, notifications) |

All Huly services use `haiodo/*` Docker images from the [intabia-fusion/foundation-selfhost](https://github.com/intabia-fusion/foundation-selfhost) PostgreSQL fork.

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
| `livekit_api_key` | password:16 | LiveKit API key (for video calls) |
| `livekit_api_secret` | base64:32 | LiveKit API secret (for video calls) |

## Optional: GitHub Integration

The GitHub service is included but dormant by default. To enable it:

### Step 1: Create a GitHub App

1. Go to https://github.com/settings/apps/new
2. Set **Callback URL**: `https://{your-domain}/github`
3. Set **Setup URL**: `https://{your-domain}/github` (check "Redirect on update")
4. Set **Webhook URL**: `https://{your-domain}/_github/api/webhook`
5. Set **Webhook secret**: `secret`
6. **Permissions** -- set all to Read & Write:
   - Commit statuses, Contents, Custom properties, Discussions
   - Issues, Pages, Projects, Pull requests, Webhooks
   - Metadata: Read-only
7. **Subscribe to events**: Issues, Pull request, Pull request review, Pull request review comment, Pull request review thread
8. Click **Create GitHub App**
9. Generate a **Private Key** (downloads a `.pem` file)

### Step 2: Set environment variables

From your GitHub App's settings page, copy the values into Dokploy's **Environment** tab:

```
GITHUB_APPID=123456
GITHUB_APPNAME=my-huly-app
GITHUB_CLIENTID=Iv1.xxxxxxxxxx
GITHUB_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GITHUB_PRIVATE_KEY=<see below>
GITHUB_BOT_NAME=my-huly-app[bot]
```

> **`GITHUB_PRIVATE_KEY` format:** Copy the PEM file content **as-is** into the env var. Replace newlines with literal `\n`.
>
> Quick conversion: `awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' your-app.private-key.pem`

### Step 3: Redeploy

## Optional: AI Assistant

The AI bot service is included but **requires `OPENAI_API_KEY` to start**. Without a valid API key, the aibot container will crash-loop -- this is expected and won't affect the rest of Huly (nginx is configured to handle optional services being down).

To enable the AI assistant, set these in your Huly app's **Environment** tab:

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | **Yes** (for AI to work) | API key for your OpenAI-compatible provider |
| `OPENAI_BASE_URL` | No | API endpoint (default: `https://api.openai.com/v1`). Change for alternative providers |
| `OPENAI_MODEL` | No | Main chat model (default: `gpt-4o-mini`) |
| `OPENAI_SUMMARY_MODEL` | No | Model for summarization (default: `gpt-4o-mini`) |
| `OPENAI_TRANSLATE_MODEL` | No | Model for translation (default: `gpt-4o-mini`) |

**Example -- OpenAI:**
```
OPENAI_API_KEY=sk-proj-...
OPENAI_MODEL=gpt-4o
OPENAI_SUMMARY_MODEL=gpt-4o-mini
```

**Example -- Ollama (local):**
```
OPENAI_API_KEY=ollama
OPENAI_BASE_URL=http://host.docker.internal:11434/v1
OPENAI_MODEL=llama3.1
OPENAI_SUMMARY_MODEL=llama3.1
```

> **Note:** If you don't need AI features, you can safely ignore the aibot crash-loop in your container logs. It won't affect other services.

The bot provides: chat, text translation, message/meeting summarization, and PDF import.

### Speech-to-Text (STT) for Video Calls

Huly can transcribe meeting audio in real-time. The **love-agent** captures audio from LiveKit and sends chunks to the **aibot** for transcription.

| Variable | Default | Description |
|----------|---------|-------------|
| `STT_PROVIDER` | *(empty -- disabled)* | Transcription backend: `openai` (Whisper API), `deepgram`, or `server` |
| `STT_URL` | *(empty)* | Custom Whisper endpoint (only for `openai` provider). Leave empty for OpenAI cloud. Set for self-hosted (e.g., `http://your-whisper:9007`) |
| `STT_API_KEY` | *(empty)* | API key for your STT provider. For `openai`: your OpenAI key. For `deepgram`: your Deepgram key |
| `STT_MODEL` | `whisper-1` / `nova-2` | Model to use. `whisper-1` for OpenAI, `nova-2` for Deepgram |
| `LOVE_AGENT_STT_PROVIDER` | `stream` | **Do not change.** The haiodo fork only supports `stream` mode |

**Example -- Use OpenAI Whisper (same key as AI assistant):**
```
STT_PROVIDER=openai
```
(Uses `OPENAI_API_KEY` automatically -- no need to set `STT_API_KEY` separately if already configured)

**Example -- Use Deepgram:**
```
STT_PROVIDER=deepgram
STT_API_KEY=your-deepgram-api-key
```

**Example -- Self-hosted Whisper (faster-whisper, etc.):**
```
STT_PROVIDER=openai
STT_URL=http://your-whisper-server:9007
STT_API_KEY=not-needed
STT_MODEL=whisper-large-v3
```

## Troubleshooting

### Login loop / Logged out on refresh

If you're still being logged out on refresh:

1. Check the nginx entrypoint logs:
   ```
   docker logs <nginx-container> | head -20
   ```
   You should see the parent domain being calculated

2. Verify the cookie domain in browser dev tools:
   - Open F12 -> Application -> Cookies
   - Check that cookies have the correct domain

### Database connection errors

Postgres needs time to initialize. The template includes health checks, but if you see connection errors, wait 30 seconds and redeploy.

### Services not starting

Check that all services are on the same Docker network. Dokploy should handle this automatically.

## Development

### Setup

```bash
git clone https://github.com/spatialy/huly-dokploy.git
cd huly-dokploy
./scripts/install-hooks.sh   # Install pre-commit hook for auto version bumping
```

### Version Bumping

A **pre-commit hook** automatically bumps the template patch version whenever you commit changes to blueprint files (`template.toml`, `docker-compose.yml`). The hook updates `VERSION`, `meta.json`, and `TEMPLATE_VERSION` in `template.toml`, then stages them into your commit.

For manual or larger bumps:

```bash
./scripts/bump-version.sh patch           # v1.1.0 -> v1.1.1 (auto on commit)
./scripts/bump-version.sh minor           # v1.1.0 -> v1.2.0
./scripts/bump-version.sh major           # v1.1.0 -> v2.0.0
./scripts/bump-version.sh huly v0.7.320   # Update Huly images + auto patch bump
```

The `huly` subcommand updates `HULY_VERSION` in `template.toml`, syncs the Huly version into the `meta.json` description, and auto-bumps the template patch version.

### File Structure

```
VERSION                            # Template semver (single source of truth)
meta.json                          # Dokploy blueprint registry (version badge + description)
scripts/
  bump-version.sh                  # Bump template or Huly version across all files
  pre-commit                       # Git hook: auto patch bump on blueprint changes
  install-hooks.sh                 # Install git hooks after cloning
blueprints/huly-v7/
  template.toml                    # Dokploy template (env vars, mounts, domains)
  docker-compose.yml               # 29 services orchestration
  huly.svg                         # Logo for Dokploy UI
```

---

## Credits

- **Original Huly**: https://github.com/hcengineering/huly
- **PostgreSQL Fork**: https://github.com/intabia-fusion/foundation-selfhost -- This template uses the intabia-fusion fork of Huly that replaces CockroachDB with PostgreSQL, making self-hosting simpler and more resource-friendly. Docker images are published as `haiodo/*` on Docker Hub.
- **Dokploy Template**: Created to help non-developers deploy Huly without headaches. If it helps you, give it a star!

## License

MIT - Use freely!
