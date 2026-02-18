#!/bin/sh
set -e

INTERVAL=${RECONCILE_INTERVAL:-300}

echo "Waiting for CockroachDB to be ready..."
until psql "$CR_DB_URL" -c "SELECT 1" > /dev/null 2>&1; do
  sleep 5
done
echo "CockroachDB is ready. Running reconciliation every ${INTERVAL}s."

while true; do
  psql "$CR_DB_URL" -c "
    UPDATE love
    SET data = jsonb_set(COALESCE(data, '{}'::jsonb), '{meetings}', (
        SELECT COALESCE(to_jsonb(count(*)), '0'::jsonb)
        FROM meeting_minutes
        WHERE \"attachedTo\" = love._id
        AND \"workspaceId\" = love.\"workspaceId\"
    )::jsonb)
    WHERE _class IN ('love:class:Room', 'love:class:Office');
  " && echo "[$(date -Iseconds)] Reconciled meeting-minutes counters" \
    || echo "[$(date -Iseconds)] Reconciliation failed"
  sleep "$INTERVAL"
done
