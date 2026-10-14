// صور المتجر (Google Play): 1080×1920 + صورة الغلاف 1024×500
import { chromium } from 'playwright';
import fs from 'node:fs';

const URL = process.env.SITE || 'https://mehtag-sanaye.web.app';
const OUT = 'webtest/store';
fs.mkdirSync(OUT, { recursive: true });
const log = [];
const L = (s) => { console.log(s); log.push(s); };
let n = 0;
const wait = (p, ms = 1800) => p.waitForTimeout(ms);

async function newPage(browser) {
  const ctx = await browser.newContext({ viewport: { width: 360, height: 640 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true, locale: 'ar-EG', geolocation: { latitude: 30.0444, longitude: 31.2357 }, permissions: ['geolocation'] });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L(`[pageerror] ${String(e).slice(0, 300)}`));
  return page;
}
async function shot(page, name) {
  const f = `${OUT}/screenshot-${String(++n).padStart(2, '0')}-${name}.png`;
  await page.screenshot({ path: f });
  L(`saved ${f}`);
}
async function click(loc) {
  try { await loc.tap({ timeout: 3000 }); } catch (_) { try { await loc.click({ timeout: 3000, force: true }); } catch (_) { await loc.evaluate((e) => e.click()); } }
}
async function tap(page, re) {
  for (const role of ['button', 'tab', 'link']) {
    const l = page.getByRole(role, { name: re });
    if (await l.count()) { await click(l.first()); await wait(page); return true; }
  }
  const t = page.getByText(re);
  if (await t.count()) { await click(t.first()); await wait(page); return true; }
  L(`(not found ${re})`);
  return false;
}
async function open(page) {
  await page.goto(`${URL}/?a11y=1`, { waitUntil: 'load', timeout: 90000 });
  await page.waitForFunction(() => !document.getElementById('splash'), null, { timeout: 90000 });
  await wait(page, 3000);
}
async function type(page, idx, text) {
  const i = page.locator('input, textarea, [role=textbox]').nth(idx);
  await click(i); await wait(page, 400);
  await page.keyboard.press('Control+A'); await page.keyboard.type(text, { delay: 15 });
}
async function login(page, roleBtn, email, pass) {
  await tap(page, /ابدأ دلوقتي/);
  await tap(page, roleBtn);
  await type(page, 0, email); await type(page, 1, pass);
  await page.keyboard.press('Enter');
  await wait(page, 7000);
}
async function back(page) { if (!(await tap(page, /^(رجوع|Back)$/))) await page.keyboard.press('Escape'); await wait(page, 1000); }

const browser = await chromium.launch();
try {
  // 1-2 الترحيب
  let p = await newPage(browser);
  await open(p);
  await shot(p, 'welcome');
  await tap(p, /ابدأ دلوقتي/);
  await p.mouse.wheel(0, 2000); await wait(p, 1200);
  await shot(p, 'choose-role');
  await p.context().close();

  // 3-8 العميل
  p = await newPage(browser);
  await open(p);
  await login(p, /أنا محتاج صنايعي/, 'demo7@mehtag-sanaye.test', process.env.DEMO_ADMIN_PASSWORD);
  await shot(p, 'customer-home');
  await tap(p, /^سباك$/); await wait(p, 3500);
  await shot(p, 'search-results');
  const card = p.getByRole('button', { name: /محمد السباك|حسن سباك/ });
  if (await card.count()) { await click(card.first()); await wait(p, 3000); await shot(p, 'worker-profile'); await back(p); }
  else L('(no worker card)');
  if (await tap(p, /^خريطة$/)) { await wait(p, 5000); await shot(p, 'map'); await back(p); }
  await back(p);
  if (await tap(p, /محتاج صنايعي الآن/)) { await wait(p, 2500); await shot(p, 'emergency'); await back(p); }
  if (await tap(p, /^حسابي/)) { await shot(p, 'account'); }
  if (await tap(p, /المساعدة والدعم/)) { await shot(p, 'help'); }
  await p.context().close();

  // 9 الصنايعي
  p = await newPage(browser);
  await open(p);
  await login(p, /أنا صنايعي وعايز أسجل/, 'webtest-worker@mehtag-sanaye.test', process.env.TEST_PASS);
  await shot(p, 'worker-signup');
  await p.context().close();

  // 10 الإدارة
  p = await newPage(browser);
  await open(p);
  await tap(p, /دخول الإدارة/);
  await type(p, 0, 'webtest-admin@mehtag-sanaye.test'); await type(p, 1, process.env.TEST_PASS);
  await p.keyboard.press('Enter'); await wait(p, 8000);
  await shot(p, 'admin');
  await p.context().close();

  // صورة الغلاف
  const fp = await (await browser.newContext({ viewport: { width: 1024, height: 500 } })).newPage();
  const logo = 'data:image/png;base64,' + fs.readFileSync('app/assets/images/brand_logo_round.png').toString('base64');
  await fp.setContent(fs.readFileSync('webtest/feature.html', 'utf8').replace('LOGO', logo), { waitUntil: 'networkidle' });
  await fp.waitForTimeout(1500);
  await fp.screenshot({ path: `${OUT}/feature-graphic-1024x500.png` });
  L('saved feature graphic');
} catch (e) { L(`FAILED ${e}`); }
await browser.close();
fs.writeFileSync(`${OUT}/log.txt`, log.join('\n'));
