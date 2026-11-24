// Generates the icon set and the 1200x630 share card from the source logo.
//
//   node scripts/generate-assets.mjs        (after `astro build`)
//
// Everything here is derived, so the only file to edit by hand is
// `public/logo.svg`. PNGs are written to `public/` (source of truth, committed)
// and copied into `dist/` so a build does not need a second pass.
import { execFile } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, writeFile, copyFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import sharp from 'sharp';

// The share card is a screenshot, which needs a local Chrome. The committed
// public/og.png is copied into dist/ like any other static file, so a build
// without Chrome (CI, Linux) still ships a card — it just skips the refresh.
const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);
const CHROME = CHROME_CANDIDATES.find((path) => existsSync(path));

const run = promisify(execFile);
const site = fileURLToPath(new URL('..', import.meta.url));
const publicDir = join(site, 'public');
const distDir = join(site, 'dist');
const hasDist = existsSync(distDir);

const INK = '#080a10';
const mark = await readFile(join(publicDir, 'logo.svg'), 'utf8');
const inner = mark.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>[\s\S]*$/, '');

const square = (background) => `<svg viewBox="0 0 680 680" xmlns="http://www.w3.org/2000/svg">
  <rect width="680" height="680" fill="${background}"/>
  ${inner}
</svg>`;

// Maskable icons need the mark inside the central 80% safe zone.
const maskable = `<svg viewBox="0 0 680 680" xmlns="http://www.w3.org/2000/svg">
  <rect width="680" height="680" fill="${INK}"/>
  <g transform="translate(68 68) scale(0.8)">${inner}</g>
</svg>`;

const favicon = square(INK);
await writeFile(join(publicDir, 'favicon.svg'), favicon);

const targets = [
  ['favicon.png', square(INK), 48],
  ['favicon-32.png', square(INK), 32],
  ['apple-touch-icon.png', square(INK), 180],
  ['icon-192.png', square(INK), 192],
  ['icon-512.png', square(INK), 512],
  ['icon-maskable-192.png', maskable, 192],
  ['icon-maskable-512.png', maskable, 512],
];

for (const [name, svg, size] of targets) {
  const png = await sharp(Buffer.from(svg)).resize(size, size).png().toBuffer();
  await writeFile(join(publicDir, name), png);
  if (hasDist) await writeFile(join(distDir, name), png);
}

// Share card: screenshot the /og/ route once the build exists.
async function shareCard() {
  const card = join(distDir, 'og', 'index.html');
  if (!existsSync(card)) {
    console.warn('skip og.png: build first so dist/og/index.html exists');
    return;
  }
  if (!CHROME) {
    console.warn('skip og.png: no Chrome found (set CHROME_PATH to refresh it)');
    return;
  }

  const types = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.avif': 'image/avif',
    '.webp': 'image/webp',
    '.woff2': 'font/woff2',
    '.webmanifest': 'application/manifest+json',
    '.xml': 'application/xml',
  };

  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://127.0.0.1');
      let path = join(distDir, decodeURIComponent(url.pathname));
      if (url.pathname.endsWith('/')) path = join(path, 'index.html');
      if (!existsSync(path) && existsSync(`${path}/index.html`)) {
        path = `${path}/index.html`;
      }
      const body = await readFile(path);
      res.writeHead(200, {
        'content-type': types[extname(path)] ?? 'application/octet-stream',
      });
      res.end(body);
    } catch {
      res.writeHead(404).end('not found');
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  const out = join(publicDir, 'og.png');

  try {
    await run(CHROME, [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--window-size=1200,630',
      '--virtual-time-budget=4000',
      `--screenshot=${out}`,
      `http://127.0.0.1:${port}/og/`,
    ]);
    await copyFile(out, join(distDir, 'og.png'));
    console.log('wrote og.png');
  } finally {
    server.close();
  }
}

await shareCard();
console.log('icons written to public/');
