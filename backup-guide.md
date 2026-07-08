# Huly Backup & Restore Guide

## How the Automated Backup Works

The `hardcoreeng/backup` service runs a scheduler loop:

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `INTERVAL` | 3600 | Backup every 1 hour |
| `TIMEOUT` | 3600 | Max 1 hour per backup operation |
| `COOL_DOWN` | 300 | Wait 5 min after failure before retry |
| `PARALLEL` | 1 | One workspace at a time |
| `KEEP_SNAPSHOTS` | 84 | Retain 84 snapshots (~3.5 days at hourly) |
| `BUCKET_NAME` | backups | MinIO bucket for storing snapshots |

**What it backs up**: Database transactions (all 63 domains), blob references, and workspace metadata. Stored as `tar.gz` chunks in MinIO under `backups/<workspace-uuid>/`.

The `backup-api` service (port 4039, exposed at `/_backup/`) provides a REST API for the Huly frontend and desktop app to list and download available backups.

---

## How to Restore from Backup

### Method A: `hardcoreeng/tool` CLI (recommended)

The `hardcoreeng/tool` container has these backup commands:

| Command | Description |
|---------|-------------|
| `backup <dir> <workspace>` | Create a backup of a workspace to local dir |
| `backup-restore <dir> <workspace> [date]` | Restore a workspace from local backup (optional point-in-time date) |
| `backup-s3-download <bucket> <dir> <storeIn>` | Download backup from S3/MinIO to local dir |
| `backup-compact <dir>` | Compact backup into single snapshot |
| `backup-s3-compact <bucket> <dir>` | Compact backup directly in S3 |
| `backup-check <dir>` | Verify backup integrity |

#### Step-by-step restore procedure (v0.7)

**Step 1 -- Download backup from MinIO to local dir:**

```bash
docker run --rm \
  --network <compose-network> \
  -e SERVER_SECRET="$SECRET" \
  -e ACCOUNTS_URL="http://account:3000" \
  -e TRANSACTOR_URL="ws://transactor:3333" \
  -e STORAGE_CONFIG="minio|minio?accessKey=minioadmin&secretKey=minioadmin" \
  -e DB_URL="$PG_DB_URL" \
  -v ./backup-local:/backup \
  hardcoreeng/tool:v0.7.382 \
  -- bundle.js backup-s3-download backups <workspace-uuid> /backup
```

**Step 2 -- Restore workspace from local backup:**

```bash
docker run --rm \
  --network <compose-network> \
  -e SERVER_SECRET="$SECRET" \
  -e ACCOUNTS_URL="http://account:3000" \
  -e TRANSACTOR_URL="ws://transactor:3333" \
  -e STORAGE_CONFIG="minio|minio?accessKey=minioadmin&secretKey=minioadmin" \
  -e DB_URL="$PG_DB_URL" \
  -e QUEUE_CONFIG="redpanda:9092" \
  -v ./backup-local:/backup \
  hardcoreeng/tool:v0.7.382 \
  -- bundle.js backup-restore /backup <workspace-url-or-id>
```

**Key options for `backup-restore`:**

- `[date]` -- optional, restore to a specific point in time
- `--merge` -- merge remote and backup content (instead of overwrite)
- `--parallel <n>` -- parallel restore operations
- `--include <domains>` -- only restore specific domains (`;` separated)
- `--skip <domains>` -- skip specific domains
- `--upgrade` -- also upgrade workspace after restore

### Method B: Manual backup via `hardcoreeng/tool backup`

Create a manual backup directly (bypasses the automated backup service):

```bash
docker run --rm \
  --network <compose-network> \
  -e SERVER_SECRET="$SECRET" \
  -e ACCOUNTS_URL="http://account:3000" \
  -e TRANSACTOR_URL="ws://transactor:3333" \
  -e STORAGE_CONFIG="minio|minio?accessKey=minioadmin&secretKey=minioadmin" \
  -e DB_URL="$PG_DB_URL" \
  -v ./my-backup:/backup \
  hardcoreeng/tool:v0.7.382 \
  -- bundle.js backup /backup <workspace-url-or-id>
```

**Key options:**

- `--blobLimit <MB>` -- blob size limit (default 5MB, use higher for full backup)
- `--full` -- full recheck (not incremental)
- `--keepSnapshots <days>` -- retention in days (default 14)
- `--include / --skip` -- filter domains

### Method C: Desktop App Backup

- In the Huly desktop app: **Menu > Backup**
- Must be workspace owner
- Downloads workspace backup to local filesystem
- Can be restored to any self-hosted instance via `backup-restore`

---

## Alternative Backup Strategies

### Strategy 1: Database + MinIO Volume Backup (simplest)

Per Huly maintainer @aonnikov ([hcengineering/huly-selfhost#223](https://github.com/hcengineering/huly-selfhost/issues/223)): *"you can backup/restore only cockroach and minIO, it will work as well."*

**For huly-v7-pg (PostgreSQL):**

```bash
# Backup database
docker exec <postgres-container> pg_dump -U huly huly > huly_backup.sql

# Backup MinIO files volume
docker run --rm -v <files-volume>:/data -v ./backup:/backup \
  alpine tar czf /backup/minio_files.tar.gz -C /data .

# Restore database
docker exec -i <postgres-container> psql -U huly huly < huly_backup.sql

# Restore MinIO files
docker run --rm -v <files-volume>:/data -v ./backup:/backup \
  alpine tar xzf /backup/minio_files.tar.gz -C /data
```

**For huly-v7-next (CockroachDB):**

```bash
# Backup CockroachDB to local node storage
cockroach sql \
  --url 'postgresql://root@cockroach:26257?sslmode=disable' \
  --execute="BACKUP INTO 'nodelocal://1/full-cluster-backup';"

# Or backup CockroachDB to S3
cockroach sql \
  --url 'postgresql://root@cockroach:26257?sslmode=disable' \
  --execute="BACKUP INTO 's3://my-backups/cockroach?AWS_ACCESS_KEY_ID=...&AWS_SECRET_ACCESS_KEY=...';"
```

**What you need to back up:**

- `pg_data` (or `cockroach_data`) -- the database (**critical**)
- `files` (MinIO volume) -- all uploaded files/blobs (**critical**)
- `elastic` -- search index (optional, can be rebuilt via `fulltext-reindex`)
- `redpanda` -- event stream (optional, replayed from DB)

### Strategy 2: Docker Volume Snapshots (host-level)

If using LVM, ZFS, or cloud block storage:

```bash
# Stop services for consistent snapshot
docker compose stop
# Snapshot all volumes at host level (LVM/ZFS/cloud-specific commands)
# Start services
docker compose start
```

### Strategy 3: MinIO Client (`mc`) for blob backup

```bash
# Configure alias
mc alias set huly http://minio:9000 minioadmin minioadmin

# Mirror all buckets to local
mc mirror huly/ /local/backup/minio/

# Mirror just the backups bucket
mc mirror huly/backups /local/backup/backups/
```

### Strategy 4: Scheduled `pg_dump` cron job

Add a sidecar or host cron:

```bash
0 */6 * * * docker exec postgres pg_dump -U huly huly | gzip > /backups/huly_$(date +\%Y\%m\%d_\%H\%M).sql.gz
```

---

## Recommended Backup Strategy

Belt-and-suspenders approach:

| Layer | Method | Frequency | Retention |
|-------|--------|-----------|-----------|
| **Application** | Built-in `backup` service | Hourly (`INTERVAL=3600`) | 84 snapshots (~3.5 days) |
| **Database** | `pg_dump` cron | Every 6 hours | 30 days |
| **Files** | MinIO `mc mirror` or volume snapshot | Daily | 14 days |
| **Full disaster recovery** | `hardcoreeng/tool backup` to external storage | Weekly | 90 days |

The built-in backup service handles routine point-in-time recovery. The `pg_dump` + MinIO mirror handles catastrophic failures where MinIO itself is lost.

---

## Offsite Replication (strongly recommended)

By default the `backups` bucket lives in the bundled MinIO on the **same disk** as the data it protects — a disk failure or compromised host loses data and backups together, and 84 hourly snapshots only cover ~3.5 days. Get a copy off the server:

**Option A — mirror the backups bucket to external S3** (Backblaze B2, Cloudflare R2, Wasabi, AWS):

```bash
# One-shot (add to cron on the host, e.g. daily):
docker run --rm --network <project>_default -e MC_HOST_src="http://$S3_ACCESS_KEY:$S3_SECRET_KEY@minio:9000" \
  -e MC_HOST_dst="https://<key>:<secret>@s3.us-west-004.backblazeb2.com" \
  minio/mc mirror --overwrite src/backups dst/<your-offsite-bucket>
```

**Option B — point the backup service directly at external S3**: change the `STORAGE`/`WORKSPACE_STORAGE` env on the `backup` and `backup-api` services to your external provider and pre-create the `backups` bucket there. Backups then never touch the local disk.

Whichever you choose, also ship the `pg_dump` output offsite — the Huly backup covers workspace data, but a plain database dump is the cheapest insurance for the account/global tables.

---

## Known Limitations & Gotchas

1. **No v0.7 `backup-all-to-dir` command** -- the v0.6 bulk command doesn't exist in v0.7. Use `backup <dir> <workspace>` per workspace.
2. **OIDC identities may not restore** -- [hcengineering/huly-selfhost#200](https://github.com/hcengineering/huly-selfhost/issues/200): after restore, `social_id` table may be missing `oidc` entries. Manual SQL fix required.
3. **`PROCEED_V7_MONGO=true` is irreversible** -- locks you into MongoDB forever, no later migration to PG/CockroachDB.
4. **Desktop app backup may show "No backups available"** -- requires the `backup` service to have created snapshots first, AND the `backup-api` to be accessible.
5. **Backup retention is snapshots, not days** -- `KEEP_SNAPSHOTS=84` means 84 snapshots regardless of time span.
6. **`backup-compact` excludes large media by default** -- skips `video/`, `application/octet-stream`, `audio/`, `image/` content types.
7. **Network name matters** -- the `--network` flag must match your compose project's network (e.g., `huly-v7-pg_default` or Dokploy's generated name like `huly-v7-pg-kq1b3e_default`).
