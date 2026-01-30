#!/usr/bin/env node
/**
 * Generate runtime public config.js from environment variables.
 *
 * Why?
 * - We don't hardcode keys in HTML.
 * - Cloudflare Pages can inject env vars at build time.
 * - Locally, you can keep keys in .env.local and generate config.js.
 *
 * Notes:
 * - Only "NEXT_PUBLIC_*" values are written (public by design).
 * - This script does NOT write any secrets (service role keys, tokens...).
 */

import fs from 'node:fs';
import path from 'node:path';

const projectRoot = process.cwd();

function parseDotEnv(filePath) {
  const out = {};
  if (!fs.existsSync(filePath)) return out;
  const raw = fs.readFileSync(filePath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    let val = trimmed.slice(idx + 1).trim();
    // strip surrounding quotes
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return out;
}

// Local dev convenience: read .env.local then .env, but env vars override.
const envLocal = parseDotEnv(path.join(projectRoot, '.env.local'));
const env = parseDotEnv(path.join(projectRoot, '.env'));

function getEnv(key) {
  return process.env[key] ?? envLocal[key] ?? env[key] ?? '';
}

const publicConfig = {
  NEXT_PUBLIC_SUPABASE_URL: getEnv('NEXT_PUBLIC_SUPABASE_URL'),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: getEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY'),
  NEXT_PUBLIC_TURNSTILE_SITE_KEY: getEnv('NEXT_PUBLIC_TURNSTILE_SITE_KEY'),
  NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID: getEnv('NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID'),
  NEXT_PUBLIC_GA_MEASUREMENT_ID: getEnv('NEXT_PUBLIC_GA_MEASUREMENT_ID'),
  NEXT_PUBLIC_META_PIXEL_ID: getEnv('NEXT_PUBLIC_META_PIXEL_ID'),
  NEXT_PUBLIC_TIKTOK_PIXEL_ID: getEnv('NEXT_PUBLIC_TIKTOK_PIXEL_ID')
};

const content = `// Runtime public config (generated)
// DO NOT put secrets here.
window.__APP_CONFIG__ = ${JSON.stringify(publicConfig, null, 2)};
`;

const outPath = path.join(projectRoot, 'config.js');
fs.writeFileSync(outPath, content, 'utf8');

const missing = Object.entries(publicConfig)
  .filter(([k, v]) => ['NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','NEXT_PUBLIC_TURNSTILE_SITE_KEY','NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID'].includes(k) && !v)
  .map(([k]) => k);

console.log(`[generate-config] Wrote ${outPath}`);
if (missing.length) {
  console.warn('[generate-config] Missing required public env vars:', missing.join(', '));
  process.exitCode = 0;
}
