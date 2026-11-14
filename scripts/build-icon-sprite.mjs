// Builds apps/landing/assets/icons/sprite.svg from @phosphor-icons/core assets.
// Usage: node scripts/build-icon-sprite.mjs <path-to-phosphor-assets>
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { gunzipSync } from 'node:zlib';

const inputArg = process.argv[2];
if (!inputArg) {
  console.error('Usage: node scripts/build-icon-sprite.mjs <path-to-phosphor-assets>');
  process.exit(1);
}

const CATEGORY_ICONS = [
  'fork-knife',
  'needle',
  'sneaker',
  't-shirt',
  'storefront',
  'shopping-bag',
  'wrench',
  'sparkle',
];

const UI_ICONS = [
  ...CATEGORY_ICONS,
  'caret-left',
  'caret-right',
  'check',
  'pause',
  'play',
];

function loadFromTarball(tgzPath) {
  const buf = gunzipSync(readFileSync(tgzPath));
  const files = new Map();
  let offset = 0;
  while (offset + 512 <= buf.length) {
    const header = buf.subarray(offset, offset + 512);
    if (header[0] === 0) break;
    const name = header.subarray(0, 100).toString('utf8').replace(/\0.*$/, '');
    const prefix = header.subarray(345, 500).toString('utf8').replace(/\0.*$/, '');
    const fullName = prefix ? `${prefix}/${name}` : name;
    const sizeOctal = header.subarray(124, 136).toString('utf8').replace(/\0.*$/, '').trim();
    const size = parseInt(sizeOctal || '0', 8) || 0;
    const dataStart = offset + 512;
    if (fullName.endsWith('.svg')) {
      const rel = fullName.replace(/^package\/assets\//, '');
      files.set(rel, buf.subarray(dataStart, dataStart + size).toString('utf8'));
    }
    offset = dataStart + Math.ceil(size / 512) * 512;
  }
  return (relPath) => {
    const content = files.get(relPath);
    if (!content) throw new Error(`Missing icon in tarball: ${relPath}`);
    return content;
  };
}

function findTarballNear(dir) {
  const candidates = [dir, dirname(dir), dirname(dirname(dir))];
  for (const d of candidates) {
    const tgz = join(d, 'phosphor-icons-core-2.1.1.tgz');
    if (existsSync(tgz)) return tgz;
  }
  return null;
}

function createReader(sourcePath) {
  const abs = resolve(sourcePath);
  const st = statSync(abs);
  if (st.isFile() && (abs.endsWith('.tgz') || abs.endsWith('.tar.gz'))) {
    return loadFromTarball(abs);
  }
  const assetsRoot = existsSync(join(abs, 'regular'))
    ? abs
    : existsSync(join(abs, 'assets', 'regular'))
      ? join(abs, 'assets')
      : existsSync(join(abs, 'package', 'assets', 'regular'))
        ? join(abs, 'package', 'assets')
        : abs;

  let tarFallback = null;
  return (relPath) => {
    const full = join(assetsRoot, relPath);
    if (existsSync(full)) {
      return readFileSync(full, 'utf8');
    }
    if (!tarFallback) {
      const nearTgz = findTarballNear(abs);
      if (nearTgz) tarFallback = loadFromTarball(nearTgz);
    }
    if (tarFallback) {
      const svg = tarFallback(relPath);
      mkdirSync(dirname(full), { recursive: true });
      writeFileSync(full, svg, 'utf8');
      return svg;
    }
    throw new Error(`Missing icon file: ${full}`);
  };
}

function toSymbol(id, rawSvg) {
  const viewBoxMatch = rawSvg.match(/viewBox="([^"]+)"/);
  const viewBox = viewBoxMatch ? viewBoxMatch[1] : '0 0 256 256';
  const inner = rawSvg
    .replace(/^[\s\S]*?<svg[^>]*>/i, '')
    .replace(/<\/svg>\s*$/i, '')
    .replace(/<rect[^>]*fill="none"[^>]*\/?>/gi, '')
    .replace(/fill="(?!none")[^"]*"/gi, 'fill="currentColor"')
    .replace(/stroke="(?!none")[^"]*"/gi, 'stroke="currentColor"')
    .trim();
  return `  <symbol id="${id}" viewBox="${viewBox}">${inner}</symbol>`;
}

const readAsset = createReader(inputArg);
const symbols = [];

for (const name of UI_ICONS) {
  const svg = readAsset(`regular/${name}.svg`);
  symbols.push(toSymbol(`ph-${name}`, svg));
}

for (const name of CATEGORY_ICONS) {
  const svg = readAsset(`duotone/${name}-duotone.svg`);
  symbols.push(toSymbol(`ph-${name}-duotone`, svg));
}

const output = [
  '<svg xmlns="http://www.w3.org/2000/svg" hidden aria-hidden="true" width="0" height="0">',
  ...symbols,
  '</svg>',
  '',
].join('\n');

const outPath = resolve('apps/landing/assets/icons/sprite.svg');
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, output, 'utf8');
console.log(`Wrote ${symbols.length} symbols to apps/landing/assets/icons/sprite.svg`);
