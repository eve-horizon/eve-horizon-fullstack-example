import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';

const requireFromApi = createRequire(new URL('../apps/api/package.json', import.meta.url));
const { Client } = requireFromApi('pg');

const databaseUrl = process.env.DATABASE_URL ?? 'postgres://app:app@localhost:5432/app_dev';
const port = Number(process.env.TEST_API_PORT ?? 3100);
const baseUrl = `http://127.0.0.1:${port}`;

const client = new Client({ connectionString: databaseUrl });
await client.connect();
try {
  await client.query(await readFile(new URL('../db/migrations/20260128000000_create_notes.sql', import.meta.url), 'utf8'));
  await client.query('TRUNCATE notes');
  await client.query(await readFile(new URL('../db/seed.sql', import.meta.url), 'utf8'));
} finally {
  await client.end();
}

const api = spawn(process.execPath, ['apps/api/dist/main.js'], {
  env: { ...process.env, DATABASE_URL: databaseUrl, PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let logs = '';
api.stdout.on('data', (chunk) => { logs += chunk.toString(); });
api.stderr.on('data', (chunk) => { logs += chunk.toString(); });

async function waitForHealth() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (api.exitCode !== null) throw new Error(`API exited early (${api.exitCode})\n${logs}`);
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok) return response.json();
    } catch {
      // The server may still be binding.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`API did not become healthy\n${logs}`);
}

try {
  assert.deepEqual(await waitForHealth(), { ok: true });

  const notesResponse = await fetch(`${baseUrl}/notes`);
  assert.equal(notesResponse.status, 200);
  const notes = await notesResponse.json();
  assert.equal(Array.isArray(notes), true);
  assert.equal(notes.length, 2);

  const unauthorised = await fetch(`${baseUrl}/notes`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'not allowed' }),
  });
  assert.equal(unauthorised.status, 401);

  const openApiResponse = await fetch(`${baseUrl}/openapi.json`);
  assert.equal(openApiResponse.status, 200);
  const openApi = await openApiResponse.json();
  assert.equal(openApi.openapi, '3.0.3');
  assert.ok(openApi.paths['/health']);

  const statusResponse = await fetch(`${baseUrl}/api/status`);
  assert.equal(statusResponse.status, 200);
  assert.deepEqual(await statusResponse.json(), {
    api: 'ok',
    database: 'ok',
    notes_count: 2,
  });

  console.log('API integration test passed: migration, fixture, health, notes, auth and OpenAPI');
} finally {
  api.kill('SIGTERM');
  await new Promise((resolve) => {
    if (api.exitCode !== null) return resolve();
    api.once('exit', resolve);
    setTimeout(() => {
      api.kill('SIGKILL');
      resolve();
    }, 5_000).unref();
  });
}
