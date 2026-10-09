// اختبار آلي لنسخة الويب: يفتح كل الشاشات، ياخد صور، ويسجل أي أخطاء
import { chromium } from 'playwright';
import fs from 'node:fs';

const URL = process.env.SITE || 'https://mehtag-sanaye.web.app';
const PASS = process.env.TEST_PASS;
const OUT = 'webtest/out';
fs.mkdirSync(OUT, { recursive: true });
const log = [];
const L = (s) => { console.log(s); log.push(s); };
let shot = 0;
let errors = [];

async function session(name, fn) {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 412, height: 860 }, locale: 'ar-EG', geolocation: { latitude: 30.0444, longitude: 31.2357 }, permissions: ['geolocation'] });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error' || /exception|error/i.test(m.text())) errors.push(`[console] ${m.text().slice(0, 400)}`); });
  page.on('pageerror', (e) => errors.push(`[pageerror] ${String(e).slice(0, 400)}`));
  L(`\n===== ${name} =====`);
  try { await fn(page); } catch (e) { L(`!! FLOW FAILED: ${String(e).slice(0, 300)}`); await snap(page, `${name}-FAILED`); }
  await browser.close();
}
async function settle(page, ms = 1800) { await page.waitForTimeout(ms); }
async function snap(page, label) {
  const f = `${String(++shot).padStart(2, '0')}-${label.replace(/[^\w؀-ۿ-]+/g, '_')}.png`;
  await page.screenshot({ path: `${OUT}/${f}` }).catch(() => {});
  const errs = errors; errors = [];
  L(`[${f}] ${label}${errs.length ? `\n   ERRORS:\n   - ${[...new Set(errs)].slice(0, 8).join('\n   - ')}` : ''}`);
}
async function buttons(page) {
  const names = await page.locator('[role=button], button, [role=tab], [role=link], [role=menuitem], [role=checkbox], [role=switch]').evaluateAll((els) => els.map((e) => (e.getAttribute('aria-label') || e.innerText || '').trim().replace(/\s+/g, ' ')).filter(Boolean));
  return [...new Set(names)];
}
async function listButtons(page, label) { L(`   buttons@${label}: ${(await buttons(page)).join(' | ').slice(0, 1500)}`); }
async function tap(page, name, { exact = false } = {}) {
  const re = exact ? new RegExp(`^\\s*${name}\\s*$`) : new RegExp(name);
  for (const role of ['button', 'tab', 'link', 'menuitem']) {
    const loc = page.getByRole(role, { name: re });
    if (await loc.count()) { await loc.first().click({ timeout: 5000 }); await settle(page); return true; }
  }
  const t = page.getByText(re);
  if (await t.count()) { await t.first().click({ timeout: 5000 }); await settle(page); return true; }
  L(`   (couldn't find "${name}")`);
  return false;
}
async function back(page) {
  if (!(await tap(page, '^(رجوع|Back)$'))) { await page.keyboard.press('Escape'); await settle(page, 800); }
}
async function open(page) {
  await page.goto(`${URL}/?a11y=1`, { waitUntil: 'load', timeout: 90000 });
  await page.waitForFunction(() => !document.getElementById('splash'), null, { timeout: 90000 });
  await settle(page, 2500);
}
async function typeInto(page, idx, text) {
  const inputs = page.locator('input, textarea, [role=textbox]');
  await inputs.nth(idx).click();
  await settle(page, 400);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(text, { delay: 20 });
}
async function login(page, role, email) {
  await tap(page, 'ابدأ دلوقتي');
  await tap(page, role === 'worker' ? 'أنا صنايعي وعايز أسجل' : 'أنا محتاج صنايعي');
  await snap(page, `${role}-login-screen`);
  await typeInto(page, 0, email);
  await typeInto(page, 1, PASS);
  await page.keyboard.press('Enter');
  await settle(page, 6000);
}
async function visitAll(page, prefix, names) {
  for (const n of names) {
    if (await tap(page, n)) { await snap(page, `${prefix}-${n}`); await listButtons(page, n); await back(page); }
  }
}

// ---------------------------------------------------------------- زائر
await session('guest', async (page) => {
  await open(page);
  await snap(page, 'welcome');
  await listButtons(page, 'welcome');
  await tap(page, 'English'); await snap(page, 'welcome-en'); await tap(page, 'العربية');
  await tap(page, 'ابدأ دلوقتي'); await snap(page, 'welcome-roles');
});

// ---------------------------------------------------------------- عميل
await session('customer', async (page) => {
  await open(page);
  await login(page, 'customer', 'webtest-customer@mehtag-sanaye.test');
  await snap(page, 'customer-home');
  await listButtons(page, 'customer-home');
  const home = await buttons(page);
  // كل زرار في الرئيسية (ماعدا التبويبات) يتفتح ونرجع
  const skip = /^(الرئيسية|طلباتي|المفضلة|حسابي|English|العربية)$/;
  for (const b of home.filter((x) => !skip.test(x)).slice(0, 25)) {
    if (await tap(page, b.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), { exact: true })) {
      await snap(page, `customer-home→${b.slice(0, 30)}`);
      await listButtons(page, b.slice(0, 30));
      await back(page);
      if (!(await page.getByRole('tab', { name: /الرئيسية/ }).count()) && !(await page.getByRole('button', { name: /الرئيسية/ }).count())) await back(page);
    }
  }
  for (const tab of ['طلباتي', 'المفضلة', 'حسابي']) {
    await tap(page, tab); await snap(page, `customer-tab-${tab}`); await listButtons(page, tab);
  }
  const acc = (await buttons(page)).filter((x) => !/خروج|حذف|Delete|Sign out|logout|الرئيسية|طلباتي|المفضلة|حسابي|عربي|EN|English|العربية/i.test(x));
  for (const b of acc.slice(0, 20)) {
    if (await tap(page, b.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), { exact: true })) {
      await snap(page, `customer-account→${b.slice(0, 30)}`); await listButtons(page, b.slice(0, 30)); await back(page);
    }
  }
});

// ---------------------------------------------------------------- صنايعي (لسه بيسجل)
await session('worker', async (page) => {
  await open(page);
  await login(page, 'worker', 'webtest-worker@mehtag-sanaye.test');
  await snap(page, 'worker-start');
  await listButtons(page, 'worker-start');
  for (let i = 0; i < 4; i++) { await page.mouse.wheel(0, 700); await settle(page, 600); await snap(page, `worker-scroll-${i}`); }
});

// ---------------------------------------------------------------- إدارة
await session('admin', async (page) => {
  await open(page);
  await tap(page, 'دخول الإدارة');
  await typeInto(page, 0, 'webtest-admin@mehtag-sanaye.test');
  await typeInto(page, 1, PASS);
  await page.keyboard.press('Enter');
  await settle(page, 7000);
  await snap(page, 'admin-home');
  await listButtons(page, 'admin-home');
  await visitAll(page, 'admin', ['الصنايعية', 'المستخدمون', 'الطلبات', 'العمولات والمدفوعات', 'الشكاوى والبلاغات', 'الدعم', 'التقييمات', 'إرسال إشعار', 'المهن والخدمات', 'المناطق', 'الإعدادات', 'فريق الإدارة والسجل']);
});

fs.writeFileSync(`${OUT}/log.txt`, log.join('\n'));
