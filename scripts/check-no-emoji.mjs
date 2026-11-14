// Fails (exit 1) if any pictograph or emoji variation selector appears in project text files.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

const ROOTS = ['apps/landing', 'apps/app/lib', 'docs', 'tasks', 'scripts', 'AGENTS.md'];
const EXT = new Set(['.html', '.css', '.js', '.mjs', '.ts', '.dart', '.md', '.svg', '.json', '.yaml', '.yml']);
const SKIP = new Set(['node_modules', '.git', 'build', '.dart_tool']);
const EMOJI = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}\u{2B55}\u{FE0F}\u{200D}\u{20E3}]/u;

let bad = 0;
function scan(path) {
  const st = statSync(path, { throwIfNoEntry: false });
  if (!st) return;
  if (st.isDirectory()) {
    for (const name of readdirSync(path)) if (!SKIP.has(name)) scan(join(path, name));
    return;
  }
  if (path !== 'AGENTS.md' && !EXT.has(extname(path))) return;
  readFileSync(path, 'utf8').split('\n').forEach((line, i) => {
    const m = line.match(EMOJI);
    if (m) {
      bad++;
      console.error(`${path}:${i + 1}: U+${m[0].codePointAt(0).toString(16).toUpperCase()}`);
    }
  });
}
ROOTS.forEach(scan);
if (bad) {
  console.error(`${bad} emoji match(es)`);
  process.exit(1);
}
console.log('no emojis found');
