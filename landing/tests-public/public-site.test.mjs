import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const publicRoot = fileURLToPath(new URL('../public/', import.meta.url));
const routes = ['', 'privacy/', 'terms/', 'support/', 'delete-account/'];
const page = route => readFile(path.join(publicRoot, route, 'index.html'), 'utf8');
const textContent = html => html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');

test('visitors can reach the public pages through accessible navigation', async () => {
  const pages = await Promise.all(routes.map(page));
  for (const html of pages) {
    assert.match(html, /<html lang="en-GB">/);
    assert.match(html, /href="#main"/);
    assert.match(html, /<main id="main"/);
    assert.equal((html.match(/<h1[\s>]/g) || []).length, 1);
    for (const route of routes.slice(1)) assert.ok(html.includes(`href="/${route}"`));
  }
});

test('visitors get a real TestFlight invitation and a clear testing status', async () => {
  const html = await page('');
  assert.match(html, /href="https:\/\/testflight.apple.com\/join\/f3MhePbf"/);
  assert.match(textContent(html), /testing candidate/i);
  assert.match(textContent(html), /TestFlight build may differ/i);
  assert.doesNotMatch(html, /apps\.apple\.com|SPOTTRTESTERS|trusted by|clinically proven|guaranteed results/i);
});

test('membership is an honest launch plan without a live website checkout', async () => {
  const text = textContent(await page(''));
  assert.match(text, /£10/);
  assert.match(text, /£200/);
  assert.match(text, /14-day/);
  assert.match(text, /eligible/i);
  assert.match(text, /launch plan/i);
  assert.match(text, /Apple.*prices/i);
  assert.doesNotMatch(text, /Buy now|Subscribe now|Redeem SPOTTRTESTERS/i);
});

test('optional website accounts do not imply synced health data or paid access', async () => {
  const text = textContent(await page(''));
  assert.match(text, /optional website account/i);
  assert.match(text, /does not sync.*workout.*video.*health/i);
  assert.match(text, /does not unlock.*membership/i);
  const deletion = textContent(await page('delete-account/'));
  assert.match(deletion, /Apple.*subscription/i);
  assert.match(deletion, /local.*data/i);
});

test('public assets remain local and every local reference resolves', async () => {
  for (const route of routes) {
    const html = await page(route);
    assert.doesNotMatch(html, /<script|\sstyle=|\son[a-z]+=/i);
    for (const match of html.matchAll(/(?:src|href)="([^"#]+)(?:#[^"]*)?"/g)) {
      const ref = match[1];
      if (/^(https:|mailto:)/.test(ref) || ref.startsWith('/account/')) continue;
      const target = path.join(publicRoot, ref.endsWith('/') ? `${ref}index.html` : ref);
      assert.ok((await stat(target)).isFile(), `${route}: missing ${ref}`);
    }
    for (const match of html.matchAll(/<(?:img|link|script)\b[^>]*(?:src|href)="([^"]+)"[^>]*>/g)) {
      if (/rel="canonical"/.test(match[0])) continue;
      assert.ok(match[1].startsWith('/'), `remote asset: ${match[1]}`);
    }
  }
});

test('current screenshots are unchanged copies with descriptive alternatives', async () => {
  const sources = ['vertical-skill-path.png', 'offline-coach-options.png'];
  for (const filename of sources) {
    const original = await readFile(new URL(`../../docs/media/offline-mvp-2026-11-05/${filename}`, import.meta.url));
    assert.deepEqual(await readFile(path.join(publicRoot, 'assets', filename)), original);
  }
  const html = await page('');
  for (const match of html.matchAll(/<img\b[^>]*>/g)) {
    assert.match(match[0], /alt="[^"]*"/);
    assert.match(match[0], /width="\d+"/);
    assert.match(match[0], /height="\d+"/);
  }
});

test('public pages are discoverable with canonical and social metadata', async () => {
  for (const route of routes) {
    const html = await page(route);
    assert.ok(html.includes(`href="https://spottr.omarchoudhry.co.uk/${route}"`));
    assert.match(html, /name="description"/);
    assert.match(html, /property="og:image"/);
  }
  assert.match(await readFile(path.join(publicRoot, 'sitemap.xml'), 'utf8'), /https:\/\/spottr.omarchoudhry.co.uk\/privacy\//);
  assert.match(await readFile(path.join(publicRoot, 'robots.txt'), 'utf8'), /Sitemap:/);
});

test('shared styling supports keyboard focus and reduced motion', async () => {
  const css = await readFile(path.join(publicRoot, 'styles.css'), 'utf8');
  for (const token of ['ink', 'muted', 'blue', 'teal', 'paper', 'line']) assert.ok(css.includes(`--${token}:`));
  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion/);
  for (const utility of ['shell', 'card', 'button']) assert.ok(css.includes(`.${utility}`));
});

test('account privacy explains expiry, recovery and account deletion boundaries', async () => {
  const privacy = textContent(await page('privacy/'));
  assert.match(privacy, /12 hours/);
  assert.match(privacy, /5 minutes/);
  assert.match(privacy, /10-minute/);
  assert.match(privacy, /hashed/);
  assert.match(privacy, /cleaned up/);
  const deletion = textContent(await page('delete-account/'));
  assert.match(deletion, /5 minutes/);
  assert.match(deletion, /Offload App/);
});

test('the expanded catalogue is explicitly a local beta capability', async () => {
  const text = textContent(await page(''));
  assert.match(text, /32 exercises/);
  assert.match(text, /13 camera-tracked/);
  assert.match(text, /local beta candidate/i);
  assert.match(text, /public TestFlight build/i);
  assert.match(text, /19.*manual or timed/i);
});

test('small abstract icons support privacy and planned membership without external assets', async () => {
  const html = await page('');
  assert.match(html, /src="\/assets\/privacy-shield\.png"/);
  assert.match(html, /src="\/assets\/membership-gem\.png"/);
  assert.match(await page('privacy/'), /src="\/assets\/privacy-shield\.png"/);
});

test('privacy identifies the purposes and lawful bases of website processing', async () => {
  const text = textContent(await page('privacy/'));
  assert.match(text, /Article 6\(1\)\(b\)/);
  assert.match(text, /Article 6\(1\)\(f\)/);
  assert.match(text, /legitimate interests/i);
  assert.match(text, /prevent.*abuse/i);
});

test('decorative web icons use compact transparent 256-pixel exports', async () => {
  for (const name of ['privacy-shield.png', 'membership-gem.png']) {
    const png = await readFile(path.join(publicRoot, 'assets', name));
    assert.equal(png.readUInt32BE(16), 256);
    assert.equal(png.readUInt32BE(20), 256);
    assert.ok([4, 6].includes(png[25]), `${name} must retain alpha`);
    assert.ok(png.byteLength < 150_000);
  }
});

test('brand icons use compact exports sized for their public surfaces', async () => {
  for (const [name, size] of [['app-icon.png', 256], ['apple-touch-icon.png', 180], ['favicon.png', 64]]) {
    const png = await readFile(path.join(publicRoot, 'assets', name));
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
    assert.ok(png.byteLength < 70_000);
  }
});
