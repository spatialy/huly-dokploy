#!/bin/sh
set -e

echo "=== Love Agent Entrypoint ==="
echo "Generating PLATFORM_TOKEN for love-agent..."

cat > /tmp/gen-token.js << 'GENTOKEN'
const crypto = require('crypto');
const http = require('http');

const SERVER_SECRET = process.env.SERVER_SECRET;
const SYSTEM_UUID = '1749089e-22e6-48de-af4e-165e18fbd2f9';
const BOT_EMAIL = 'huly.ai.bot@hc.engineering';

// --- HS256 JWT (same as Huly's jwt-simple) ---
function b64url(buf) {
  return (Buffer.isBuffer(buf) ? buf : Buffer.from(buf))
    .toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}
function signJWT(payload, secret) {
  const h = b64url(JSON.stringify({ typ: 'JWT', alg: 'HS256' }));
  const p = b64url(JSON.stringify(payload));
  const sig = b64url(crypto.createHmac('sha256', secret).update(h + '.' + p).digest());
  return h + '.' + p + '.' + sig;
}

// --- HTTP helpers ---
function post(host, port, body, token) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data)
    };
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const req = http.request({ hostname: host, port, method: 'POST', path: '/', headers }, (res) => {
      let chunks = '';
      res.on('data', c => chunks += c);
      res.on('end', () => {
        try { resolve(JSON.parse(chunks)); }
        catch (e) { reject(new Error('Bad JSON: ' + chunks.slice(0, 200))); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function getToken() {
  // --- Method 1: login RPC (object params, v0.7.353 format) ---
  const r1 = await post('account', 3000, {
    method: 'login',
    params: { email: BOT_EMAIL, password: 'password' }
  });
  if (r1.result) {
    const t = typeof r1.result === 'string' ? r1.result : r1.result.token;
    if (t) { process.stderr.write('Method 1 (login) succeeded\n'); return t; }
  }
  process.stderr.write('Method 1 (login) failed: ' + JSON.stringify(r1).slice(0, 300) + '\n');

  // --- Method 2: generate system JWT, find ai-bot personUuid, mint token ---
  if (!SERVER_SECRET) throw new Error('SERVER_SECRET not set, cannot generate JWT');
  const sysToken = signJWT({ account: SYSTEM_UUID, extra: { service: 'love-agent' } }, SERVER_SECRET);

  // Try findPersonBySocialKey with different param names
  for (const paramName of ['key', 'socialKey']) {
    const r2 = await post('account', 3000, {
      method: 'findPersonBySocialKey',
      params: { [paramName]: 'email:' + BOT_EMAIL }
    }, sysToken);
    if (r2.result) {
      const uuid = typeof r2.result === 'string' ? r2.result : r2.result.uuid || r2.result;
      if (uuid && typeof uuid === 'string') {
        process.stderr.write('Method 2 (findPersonBySocialKey/' + paramName + ') found: ' + uuid + '\n');
        return signJWT({ account: uuid, extra: { service: 'love-agent' } }, SERVER_SECRET);
      }
    }
    process.stderr.write('findPersonBySocialKey(' + paramName + '): ' + JSON.stringify(r2).slice(0, 300) + '\n');
  }

  // Try getPerson as another fallback
  const r3 = await post('account', 3000, {
    method: 'getPerson',
    params: { email: BOT_EMAIL }
  }, sysToken);
  if (r3.result) {
    const uuid = typeof r3.result === 'string' ? r3.result :
      (r3.result.uuid || r3.result.personUuid || r3.result._id);
    if (uuid && typeof uuid === 'string') {
      process.stderr.write('Method 2 (getPerson) found: ' + uuid + '\n');
      return signJWT({ account: uuid, extra: { service: 'love-agent' } }, SERVER_SECRET);
    }
  }
  process.stderr.write('getPerson: ' + JSON.stringify(r3).slice(0, 300) + '\n');

  throw new Error('All methods failed');
}

async function main() {
  for (let attempt = 1; attempt <= 60; attempt++) {
    try {
      const token = await getToken();
      process.stdout.write(token);
      return;
    } catch (e) {
      process.stderr.write('Attempt ' + attempt + '/60: ' + e.message + '\n');
    }
    await sleep(5000);
  }
  process.stderr.write('FATAL: Could not generate PLATFORM_TOKEN after 60 attempts\n');
  process.exit(1);
}

main();
GENTOKEN

PLATFORM_TOKEN=$(node /tmp/gen-token.js)
export PLATFORM_TOKEN
rm -f /tmp/gen-token.js

if [ -z "$PLATFORM_TOKEN" ]; then
  echo "ERROR: PLATFORM_TOKEN is empty"
  exit 1
fi

echo "PLATFORM_TOKEN generated successfully (${#PLATFORM_TOKEN} chars)"
echo "Starting love-agent..."
exec node /usr/src/app/index.js start
