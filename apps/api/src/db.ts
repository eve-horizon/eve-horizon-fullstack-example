import { Pool } from 'pg';

const rawDatabaseUrl = process.env.DATABASE_URL ?? '';
if (!rawDatabaseUrl) {
  throw new Error('DATABASE_URL is required');
}

// Trust the URL: hosted managed DBs set sslmode=require; local k3d managed
// DBs omit sslmode entirely (plain in-cluster Postgres). pg v8 treats
// sslmode=require as verify-full, which fails without the provider's CA
// cert, so downgrade to no-verify until the platform trust store lands
// (see managed-db-tls-trust-plan).
const sslmode = /[?&]sslmode=([a-z-]+)/.exec(rawDatabaseUrl)?.[1];
const wantsSsl = sslmode !== undefined && sslmode !== 'disable';
const databaseUrl = wantsSsl
  ? rawDatabaseUrl.replace(/sslmode=[^&]+/, 'sslmode=no-verify')
  : rawDatabaseUrl;

export const pool = new Pool({
  connectionString: databaseUrl,
  ssl: wantsSsl ? { rejectUnauthorized: false } : false,
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});
