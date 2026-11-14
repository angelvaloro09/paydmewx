// Differential parity run: same HTTP scenario against Node (apps/api) and Spring (apps/api-spring).
// Both talk to stub pey/LLM servers; Node uses a temp libsql file, Spring a throwaway Postgres 17 (Docker).
// Usage: node scripts/parity/run.mjs [--no-build] [--verbose]
// Exit 0 = no unaccepted diffs. Report JSON: .claude/parity/report.json
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeNormalizer, diff, startPeyStub, startLlmStub, waitForHealth } from './lib.mjs';
import { scenario } from './scenario.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const args = new Set(process.argv.slice(2));
const VERBOSE = args.has('--verbose');
const WORK = path.join(os.tmpdir(), 'paydmex-parity');
const PG_NAME = 'paydmex-parity-pg';
const PG_PORT = 55432;
const SECRET = 'whsec_' + Buffer.from('parity-webhook-secret-0123456789').toString('base64');
const JWT_SECRET = 'parity-jwt-secret-0123456789-abcdefghij';
const DOCKER_BIN = 'C:\\Program Files\\Docker\\Docker\\resources\\bin';
const env0 = { ...process.env, PATH: `${process.env.PATH ?? ''}${path.delimiter}${DOCKER_BIN}` };

const children = [];
const stubs = [];
let pgStarted = false;

function sh(cmd, cwd, label) {
  const r = spawnSync(cmd, { cwd, shell: true, env: env0, encoding: 'utf8' });
  if (r.status !== 0) {
    throw new Error(`${label} failed (exit ${r.status}):\n${(r.stdout + r.stderr).split('\n').slice(-25).join('\n')}`);
  }
  return r.stdout;
}

function launch(name, cmd, cmdArgs, cwd, env) {
  const log = fs.openSync(path.join(WORK, `${name}.log`), 'w');
  const child = spawn(cmd, cmdArgs, { cwd, env, stdio: ['ignore', log, log], windowsHide: true });
  children.push(child);
  return child;
}

function cleanup() {
  for (const c of children) {
    if (c.pid && c.exitCode === null) spawnSync('taskkill', ['/PID', String(c.pid), '/T', '/F'], { stdio: 'ignore' });
  }
  for (const s of stubs) s.close();
  if (pgStarted) spawnSync(`docker rm -f ${PG_NAME}`, { shell: true, env: env0, stdio: 'ignore' });
}
process.on('SIGINT', () => { cleanup(); process.exit(130); });

function makeTarget(name, baseUrl, pey, llm) {
  const { norm } = makeNormalizer();
  const entries = [];
  const push = (e) => entries.push(e);
  async function call(label, method, p, { token, body, raw, headers = {} } = {}) {
    const h = { ...headers };
    if (token) h.authorization = `Bearer ${token}`;
    let payload;
    if (raw !== undefined) {
      payload = raw;
      h['content-type'] ??= 'application/json';
    } else if (body !== undefined) {
      payload = JSON.stringify(body);
      h['content-type'] = 'application/json';
    }
    const res = await fetch(baseUrl + p, { method, headers: h, body: payload });
    const text = await res.text();
    let json = null;
    if (text !== '') {
      try { json = JSON.parse(text); } catch { json = { __nonJson: text.slice(0, 200) }; }
    }
    push({ label, status: res.status, ct: (res.headers.get('content-type') ?? '').split(';')[0], body: norm(json) });
    return { status: res.status, body: json };
  }
  return {
    name, entries,
    t: {
      call, pey: pey.state, llm: llm.state, secret: SECRET,
      check: (label, ok) => push({ label: `check: ${label}`, status: 'check', ct: '', body: Boolean(ok) }),
      record: (label, value) => push({ label: `record: ${label}`, status: 'record', ct: '', body: norm(value) }),
    },
  };
}

function loadAccepted() {
  const file = path.join(ROOT, 'scripts/parity/known-deviations.json');
  return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : [];
}

function compare(nodeEntries, springEntries, accepted) {
  const key = (list) => {
    const seen = new Map();
    return list.map((e) => {
      const n = (seen.get(e.label) ?? 0) + 1;
      seen.set(e.label, n);
      return [`${e.label}${n > 1 ? ` #${n}` : ''}`, e];
    });
  };
  const a = new Map(key(nodeEntries));
  const b = new Map(key(springEntries));
  const results = [];
  for (const label of new Set([...a.keys(), ...b.keys()])) {
    const x = a.get(label);
    const y = b.get(label);
    if (!x || !y) { results.push({ label, diffs: [{ path: '(step)', node: x ? 'present' : 'missing', spring: y ? 'present' : 'missing' }] }); continue; }
    const diffs = [];
    if (x.status !== y.status) diffs.push({ path: '(status)', node: x.status, spring: y.status });
    if (x.ct !== y.ct) diffs.push({ path: '(content-type)', node: x.ct, spring: y.ct });
    diff(x.body, y.body, '$', diffs);
    results.push({ label, node: x, spring: y, diffs });
  }
  for (const r of results) {
    r.accepted = [];
    r.open = [];
    for (const d of r.diffs) {
      const code = r.node?.body?.error?.code;
      const hit = accepted.find((k) => r.label.startsWith(k.step)
        && (!k.codes || k.codes.includes(code))
        && (!k.path || d.path.startsWith(k.path))
        && (!k.pathRe || new RegExp(k.pathRe).test(d.path)));
      (hit ? r.accepted : r.open).push(hit ? { ...d, reason: hit.reason } : d);
    }
  }
  return results;
}

const short = (v) => {
  const s = typeof v === 'string' ? JSON.stringify(v) : JSON.stringify(v);
  return s && s.length > 160 ? `${s.slice(0, 157)}...` : s;
};

async function main() {
  fs.mkdirSync(WORK, { recursive: true });
  if (!args.has('--no-build')) {
    console.log('build: node (tsc) + spring (mvn package, skip tests)');
    sh('npm run build --silent', path.join(ROOT, 'apps/api'), 'node build');
    sh('mvn -q -B -DskipTests package', path.join(ROOT, 'apps/api-spring'), 'spring build');
  }
  const jar = fs.readdirSync(path.join(ROOT, 'apps/api-spring/target')).find((f) => /^api-spring-.*\.jar$/.test(f) && !f.endsWith('.original'));
  if (!jar) throw new Error('Spring jar not found; run without --no-build');

  // Throwaway Postgres for Spring.
  spawnSync(`docker rm -f ${PG_NAME}`, { shell: true, env: env0, stdio: 'ignore' });
  sh(`docker run -d --rm --name ${PG_NAME} -p ${PG_PORT}:5432 -e POSTGRES_PASSWORD=parity postgres:17-alpine`, ROOT, 'docker postgres');
  pgStarted = true;
  for (let i = 0; i < 60; i++) {
    const r = spawnSync(`docker exec ${PG_NAME} pg_isready -h 127.0.0.1 -U postgres`, { shell: true, env: env0 });
    if (r.status === 0) break;
    if (i === 59) throw new Error('postgres did not become ready');
    await new Promise((r2) => setTimeout(r2, 1000));
  }

  const nodeStubs = { pey: await startPeyStub(8811), llm: await startLlmStub(8821) };
  const springStubs = { pey: await startPeyStub(8812), llm: await startLlmStub(8822) };
  stubs.push(nodeStubs.pey, nodeStubs.llm, springStubs.pey, springStubs.llm);

  const common = (port, peyPort, llmPort) => ({
    PORT: String(port),
    JWT_SECRET,
    PEY_BASE_URL: `http://127.0.0.1:${peyPort}`,
    PEY_API_KEY: 'parity-pey-key',
    PEY_WEBHOOK_SECRET: SECRET,
    PEY_TEST_AMOUNT_OVERRIDE: '',
    LLM_BASE_URL: `http://127.0.0.1:${llmPort}`,
    LLM_API_KEY: 'parity-llm-key',
    LLM_MODEL: 'parity-model',
    ENABLE_DEV_ROUTES: 'true',
  });
  const nodeDb = path.join(WORK, 'node.db');
  for (const f of [nodeDb, `${nodeDb}-journal`, `${nodeDb}-wal`, `${nodeDb}-shm`]) fs.rmSync(f, { force: true });

  const t0 = Date.now();
  launch('node', process.execPath, ['dist/index.js'], path.join(ROOT, 'apps/api'), {
    ...env0, ...common(8801, 8811, 8821), HOST: '127.0.0.1', DATABASE_URL: `file:${nodeDb.replace(/\\/g, '/')}`, DATABASE_AUTH_TOKEN: '', NODE_ENV: 'development',
  });
  launch('spring', 'java', ['-jar', path.join(ROOT, 'apps/api-spring/target', jar)], ROOT, {
    ...env0, ...common(8802, 8812, 8822),
    DATABASE_URL: `jdbc:postgresql://127.0.0.1:${PG_PORT}/postgres`, DATABASE_USERNAME: 'postgres', DATABASE_PASSWORD: 'parity',
  });
  const [nodeUp, springUp] = await Promise.all([
    waitForHealth('http://127.0.0.1:8801', 30_000, 'node'),
    waitForHealth('http://127.0.0.1:8802', 120_000, 'spring'),
  ]);
  console.log(`startup: node ${nodeUp - t0} ms, spring ${springUp - t0} ms (JVM + Flyway on local Postgres)`);

  const node = makeTarget('node', 'http://127.0.0.1:8801', nodeStubs.pey, nodeStubs.llm);
  const spring = makeTarget('spring', 'http://127.0.0.1:8802', springStubs.pey, springStubs.llm);
  for (const tg of [node, spring]) {
    try {
      await scenario(tg.t);
    } catch (err) {
      console.error(`scenario crashed on ${tg.name}: ${err.message}`);
      for (const e of tg.entries.slice(-3)) console.error(`  last: ${e.label} -> ${e.status} ${short(e.body)}`);
      tg.entries.push({ label: 'SCENARIO CRASH', status: 'crash', ct: '', body: err.message });
    }
  }

  const results = compare(node.entries, spring.entries, loadAccepted());
  const open = results.filter((r) => r.open.length);
  const accepted = results.filter((r) => !r.open.length && r.accepted.length);
  const same = results.length - open.length - accepted.length;

  fs.mkdirSync(path.join(ROOT, '.claude/parity'), { recursive: true });
  fs.writeFileSync(path.join(ROOT, '.claude/parity/report.json'), JSON.stringify(results, null, 2));

  for (const r of open) {
    console.log(`\n[DIFF] ${r.label}`);
    for (const d of r.open) console.log(`  ${d.path}\n    node:   ${short(d.node)}\n    spring: ${short(d.spring)}`);
  }
  if (VERBOSE) for (const r of accepted) console.log(`[accepted] ${r.label}: ${r.accepted.map((d) => d.reason).join('; ')}`);
  console.log(`\nparity: ${results.length} steps | identical ${same} | accepted ${accepted.length} | DIFFERENT ${open.length}`);
  console.log(`logs: ${WORK}  report: .claude/parity/report.json`);
  return open.length === 0 ? 0 : 1;
}

main()
  .then((code) => { cleanup(); process.exit(code); })
  .catch((err) => {
    console.error(VERBOSE ? err.stack : err.stack.split('\n').slice(0, 5).join('\n'));
    for (const n of ['node', 'spring']) {
      const f = path.join(WORK, `${n}.log`);
      if (fs.existsSync(f)) console.error(`--- ${n}.log (tail) ---\n${fs.readFileSync(f, 'utf8').split('\n').slice(-15).join('\n')}`);
    }
    cleanup();
    process.exit(2);
  });
