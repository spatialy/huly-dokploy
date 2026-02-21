-- KVS compatibility: CockroachDB's "bytes" type maps to PostgreSQL's "bytea"
-- The hulykvs service uses "bytes" in its V1 migration DDL. This domain alias
-- lets the migration run unmodified on PostgreSQL.
CREATE DOMAIN bytes AS bytea;
