// Parity harness helpers: stub servers (pey, LLM), normalization and structural diff.
import http from 'node:http';
import crypto from 'node:crypto';

const ULID = /[0-9A-HJKMNP-TV-Z]{26}/g;
const ULID_EXACT = /^[0-9A-HJKMNP-TV-Z]{26}$/;
const JWT = /^eyJ[\w-]+\.[\w-]+\.[\w-]+$/;
// Fields whose value is a wall-clock unix timestamp: compared as "present", not by value.
const TS_KEYS = new Set([
  'createdAt', 'updatedAt', 'paidAt', 'expiresAt', 'readyAt', 'deliveredAt', 'cancelledAt',
  'receivedAt', 'estimatedReadyAt', 'from', 'to',
]);

export function makeNormalizer() {
  const ids = new Map();
  const idOf = (raw) => {
    if (!ids.has(raw)) ids.set(raw, `<id${ids.size + 1}>`);
    return ids.get(raw);
  };
  const str = (s) => {
    if (JWT.test(s)) return '<jwt>';
    if (ULID_EXACT.test(s)) return idOf(s);
    return s.replace(ULID, (m) => idOf(m));
  };
  const walk = (v, key) => {
    if (v === null || v === undefined) return v ?? null;
    if (typeof v === 'string') return str(v);
    if (typeof v === 'number') return key && TS_KEYS.has(key) ? '<ts>' : v;
    if (Array.isArray(v)) return v.map((x) => walk(x, key));
    if (typeof v === 'object') {
      const out = {};
      for (const k of Object.keys(v).sort()) out[k] = walk(v[k], k);
      return out;
    }
    return v;
  };
  return { norm: (v) => walk(v), idOf };
}

/** Structural diff, key-order insensitive. Returns [{path, node, spring}]. */
export function diff(a, b, path = '$', out = []) {
  if (JSON.stringify(a) === JSON.stringify(b)) return out;
  const isObj = (x) => x && typeof x === 'object' && !Array.isArray(x);
  if (isObj(a) && isObj(b)) {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      if (!(k in a)) out.push({ path: `${path}.${k}`, node: '<missing>', spring: b[k] });
      else if (!(k in b)) out.push({ path: `${path}.${k}`, node: a[k], spring: '<missing>' });
      else diff(a[k], b[k], `${path}.${k}`, out);
    }
  } else if (Array.isArray(a) && Array.isArray(b) && a.length === b.length) {
    a.forEach((x, i) => diff(x, b[i], `${path}[${i}]`, out));
  } else {
    out.push({ path, node: a, spring: b });
  }
  return out;
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  });
}

function listen(server, port) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server));
  });
}

/** Fake pey: POST /codi/qr and POST /bank-account. `failNext` makes the next /codi/qr return a pey error. */
export async function startPeyStub(port) {
  const state = { requests: [], qrSeq: 0, bankSeq: 0, failNext: false };
  const server = http.createServer(async (req, res) => {
    const raw = await readBody(req);
    let body = null;
    try { body = JSON.parse(raw); } catch { /* keep null */ }
    state.requests.push({ method: req.method, url: req.url, auth: req.headers.authorization, body });
    const send = (status, obj) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(obj));
    };
    if (req.url === '/codi/qr') {
      if (state.failNext) {
        state.failNext = false;
        return send(422, { error: { message: 'Insufficient funds stub', type: 'invalid_request', requestId: 'req_parity' } });
      }
      state.qrSeq += 1;
      return send(200, { id: `qr_stub_${state.qrSeq}`, qrString: `0002parity-qr-${state.qrSeq}`, qrImage: null });
    }
    if (req.url === '/bank-account') {
      return send(200, { id: `ba_stub_${state.bankSeq += 1}`, codiStatus: 'PENDING' });
    }
    return send(404, { error: { message: 'not found', type: 'not_found', requestId: 'req_404' } });
  });
  await listen(server, port);
  return { state, close: () => server.close() };
}

/**
 * Fake OpenAI-compatible LLM. `script` is a queue of assistant messages returned in order;
 * when empty it answers a plain text reply. Every request body is recorded.
 */
export async function startLlmStub(port) {
  const state = { requests: [], script: [] };
  const server = http.createServer(async (req, res) => {
    const raw = await readBody(req);
    let body = null;
    try { body = JSON.parse(raw); } catch { /* keep null */ }
    state.requests.push({ url: req.url, auth: req.headers.authorization, body });
    const next = state.script.shift();
    const message = typeof next === 'function' ? next(body) : (next ?? { role: 'assistant', content: 'Listo.' });
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      id: 'chatcmpl-parity',
      object: 'chat.completion',
      choices: [{ index: 0, finish_reason: message.tool_calls ? 'tool_calls' : 'stop', message }],
    }));
  });
  await listen(server, port);
  return { state, close: () => server.close() };
}

export function toolCall(name, args, id = 'call_1') {
  return { role: 'assistant', content: null, tool_calls: [{ id, type: 'function', function: { name, arguments: JSON.stringify(args) } }] };
}

/** Standard Webhooks signature (v1,base64(hmac-sha256(secretBytes, "id.ts.body"))). */
export function signWebhook(secret, id, ts, rawBody) {
  const bytes = Buffer.from(secret.replace(/^whsec_/, ''), 'base64');
  const sig = crypto.createHmac('sha256', bytes).update(`${id}.${ts}.${rawBody}`, 'utf8').digest('base64');
  return { 'webhook-id': id, 'webhook-timestamp': String(ts), 'webhook-signature': `v1,${sig}` };
}

/** Valid 18-digit CLABE: bank(3) + plaza(3) + account(11) + control digit. */
export function makeClabe(first17 = '00201000000000001') {
  const w = [3, 7, 1];
  const sum = [...first17].reduce((s, d, i) => s + ((Number(d) * w[i % 3]) % 10), 0);
  return first17 + String((10 - (sum % 10)) % 10);
}

export function deriveNumRef(orderId) {
  let hash = 0;
  for (let i = 0; i < orderId.length; i++) hash = (Math.imul(hash, 31) + orderId.charCodeAt(i)) >>> 0;
  return String(1000000 + (hash % 9000000));
}

export async function waitForHealth(url, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${url}/health`);
      if (r.ok) return Date.now();
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`${label} did not become healthy at ${url} within ${timeoutMs} ms`);
}
