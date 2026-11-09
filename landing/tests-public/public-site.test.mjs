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
  assert.match(text, /Apple membership/i);
  assert.match(text, /Apple.*prices/i);
  assert.doesNotMatch(text, /Buy now|Subscribe now|Redeem SPOTTRTESTERS/i);
});

test('native account requirement keeps personal history local and purchases separate', async () => {
  const text = textContent(await page(''));
  assert.match(text, /account.*required.*start/i);
  assert.match(text, /history.*video.*health.*stay.*device/i);
  assert.match(text, /account.*does not unlock.*membership/i);
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

test('current screenshots retain provenance and descriptive alternatives', async () => {
  const { createHash } = await import('node:crypto');
  const provenance = JSON.parse(await readFile(new URL('../screenshot-provenance.json', import.meta.url), 'utf8'));
  assert.equal(provenance.length, 2);
  for (const item of provenance) {
    const bytes = await readFile(new URL('../' + item.file, import.meta.url));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
    assert.equal(bytes.readUInt32BE(16), item.width);
    assert.equal(bytes.readUInt32BE(20), item.height);
    assert.match(item.data, /illustrative local test input/);
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
  assert.match(text, /53 exercises/);
  assert.match(text, /52 camera/);
  assert.match(text, /local beta candidate/i);
  assert.match(text, /public TestFlight build/i);
  assert.match(text, /manual.*timed/i);
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

test('all notices remove optional accounts and explain independent adult statistics controls',async()=>{
 for(const route of [...routes,'account/']) assert.doesNotMatch(await page(route), /optional (?:Spottr )?website account|not required for the app|without a website account|not needed for core offline/i);
 const privacy=textContent(await page('privacy/'));
 for(const fragment of [/two independent/i,/off by default/i,/under.18.*unknown/i,/ten contributing installations.*bucket/i,/pseudonymous/i,/28 days/i,/Amazon (?:Simple Email Service|SES)/i,/recipient.*verification code/i,/backup.excluded/i]) assert.match(privacy,fragment);
 assert.doesNotMatch(privacy,/Resend|free (?:mail|email|service)/i);
});


test('visitors get a clear workout sequence and one concise disclosure for both real screens', async () => {
  const html = await page('');
  const journey = html.match(/<ol\b[^>]*aria-label="Your workout with Spottr"[^>]*>([\s\S]*?)<\/ol>/)?.[1];
  assert.ok(journey, 'Explain the workout as one accessible ordered journey');
  const steps = [...journey.matchAll(/<li\b[^>]*>([\s\S]*?)<\/li>/g)].map(match => textContent(match[1]));
  assert.equal(steps.length, 3);
  assert.match(steps[0], /programme|plan/i);
  assert.match(steps[1], /camera.*manual|manual.*camera/i);
  assert.match(steps[2], /saved.*progress|progress.*saved/i);
  const disclosures = [...html.matchAll(/<figcaption\b[^>]*id="screen-disclosure"[^>]*>([\s\S]*?)<\/figcaption>/g)];
  assert.equal(disclosures.length, 1);
  const disclosure = textContent(disclosures[0][1]).trim();
  assert.ok(disclosure.split(/\s+/).length <= 24, 'Keep the screen caption concise');
  assert.match(disclosure, /illustrative.*simulator/i);
  assert.match(disclosure, /TestFlight build may differ/i);
  for (const asset of ['today-programme.png', 'coach-programme.png']) {
    const screen = [...html.matchAll(/<img\b[^>]*>/g)].find(match => match[0].includes(asset))?.[0];
    assert.ok(screen);
    assert.match(screen, /aria-describedby="screen-disclosure"/);
  }
});

test('plan comparison leads to one account and membership help answer with actionable destinations', async () => {
  const html = await page('');
  const pricing = html.match(/<section\b[^>]*id="membership"[^>]*>([\s\S]*?)<\/section>/)?.[1];
  assert.ok(pricing);
  assert.match(pricing, /href="#account-membership"[^>]*>Account and membership help<\/a>/);
  assert.match(textContent(pricing), /account and verified Apple membership are required to start workouts/i);
  assert.match(textContent(pricing), /Apple approval and availability.*pending/i);
  assert.match(textContent(pricing), /renews until cancelled/i);
  assert.match(textContent(pricing), /does not cancel an existing monthly subscription/i);
  assert.match(textContent(pricing), /Apple purchase screen.*actual prices, terms and eligibility/i);
  const answers = [...html.matchAll(/<details\b[^>]*id="account-membership"[^>]*>([\s\S]*?)<\/details>/g)];
  assert.equal(answers.length, 1);
  const answer = answers[0][1];
  assert.match(answer, /<summary>How do my account and membership work\?<\/summary>/);
  assert.match(textContent(answer), /Apple or a verified email.*passkey and Authenticator/i);
  assert.match(textContent(answer), /TestFlight.*does not.*paid entitlement/i);
  assert.match(answer, /href="\/account\/"/);
  assert.match(answer, /href="\/support\/"/);
});

test('real app screenshots remain upright and uncropped in their presentation rules', async () => {
  const css = await readFile(path.join(publicRoot, 'styles.css'), 'utf8');
  const screenRules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
    .filter(([, selectors]) => /\.(?:phone|hero-stage|coach-scene)\b/.test(selectors));
  assert.ok(screenRules.length > 0);
  for (const [, selectors, declarations] of screenRules) {
    assert.doesNotMatch(declarations, /rotate\(|object-fit\s*:\s*cover|overflow\s*:\s*(?:hidden|clip)|clip-path\s*:/, selectors.trim());
  }
});
