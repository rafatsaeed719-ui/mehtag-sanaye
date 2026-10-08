'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const geo = require('../src/lib/geo');
const { computeCommission, sumMoney } = require('../src/lib/commission');
const sm = require('../src/lib/statusMachine');
const { computeBadges } = require('../src/lib/badges');
const v = require('../src/lib/validate');
const { render } = require('../src/lib/i18n');

// ------------------------------------------------------------- Geo
test('geohash encode matches known values', () => {
  assert.equal(geo.encode(57.64911, 10.40744, 11), 'u4pruydqqvj'); // reference value from geohash spec
  assert.equal(geo.encode(30.0444, 31.2357, 5).length, 5);
});

test('distance Cairo → Alexandria ≈ 180km', () => {
  const km = geo.distanceKm(30.0444, 31.2357, 31.2001, 29.9187);
  assert.ok(km > 170 && km < 190, `got ${km}`);
});

test('queryBounds covers every point inside the radius (randomized)', () => {
  const center = { lat: 30.0444, lng: 31.2357 };
  for (const radius of [0.5, 2, 5, 15, 25, 60]) {
    const bounds = geo.queryBounds(center.lat, center.lng, radius);
    for (let i = 0; i < 2000; i++) {
      const ang = Math.random() * 2 * Math.PI;
      const r = Math.sqrt(Math.random()) * radius;
      const lat = center.lat + (r / 111.32) * Math.cos(ang);
      const lng = center.lng + (r / (111.32 * Math.cos(center.lat * Math.PI / 180))) * Math.sin(ang);
      if (geo.distanceKm(center.lat, center.lng, lat, lng) > radius) continue;
      const h = geo.encode(lat, lng, 10);
      assert.ok(bounds.some(([s, e]) => h >= s && h <= e), `radius ${radius}: point ${lat},${lng} (${h}) not covered`);
    }
    assert.ok(bounds.length <= 9);
  }
});

test('isInEgypt', () => {
  assert.equal(geo.isInEgypt(30.04, 31.23), true);
  assert.equal(geo.isInEgypt(51.5, -0.12), false);
});

// ------------------------------------------------------------- Commission
test('5% of 500 = 25', () => {
  const c = computeCommission(500, 0.05);
  assert.equal(c.commission, 25);
  assert.equal(c.price, 500);
});

test('commission rounding to piasters', () => {
  assert.equal(computeCommission(333.33, 0.05).commission, 16.67);
  assert.equal(computeCommission(0.1, 0.05).commission, 0.01);
  assert.equal(computeCommission('1250', 0.05).commission, 62.5);
});

test('commission rejects bad input', () => {
  for (const bad of [0, -5, NaN, Infinity, 'abc', 2000000]) {
    assert.throws(() => computeCommission(bad, 0.05), /invalid-price/);
  }
  assert.throws(() => computeCommission(100, 0.9), /invalid-rate/);
  assert.throws(() => computeCommission(100, -0.1), /invalid-rate/);
});

test('sumMoney avoids float drift', () => {
  assert.equal(sumMoney([0.1, 0.2]), 0.3);
  assert.equal(sumMoney([16.67, 25, 8.33]), 50);
});

// ------------------------------------------------------------- Status machine
function apply(r, action, role, payload) {
  const t = sm.transition(r, action, role, payload, Date.now());
  return { ...r, ...t.patch, _meta: t.meta };
}

test('full happy path: customer → worker → price → commission', () => {
  let r = { status: 'new', customerId: 'c1', workerId: 'w1', open: false };
  assert.equal(sm.actorRole(r, 'c1'), 'customer');
  assert.equal(sm.actorRole(r, 'w1'), 'worker');
  assert.equal(sm.actorRole(r, 'x'), null);

  r = apply(r, 'accept', 'worker');
  assert.equal(r.status, 'accepted');
  r = apply(r, 'on_the_way', 'worker');
  r = apply(r, 'start', 'worker');
  r = apply(r, 'complete', 'worker');
  assert.equal(r.status, 'completed');
  r = apply(r, 'set_price', 'worker', { price: 500 });
  assert.equal(r.status, 'price_set');
  assert.equal(r.agreedPrice, 500);
  r = apply(r, 'confirm_price', 'customer');
  assert.equal(r.status, 'price_agreed');
  assert.equal(r._meta.createCommission, true);
  const c = computeCommission(r.agreedPrice, 0.05);
  assert.equal(c.commission, 25);
  assert.ok(sm.REVIEWABLE.includes(r.status));
});

test('roles are enforced', () => {
  const r = { status: 'new', customerId: 'c1', workerId: 'w1' };
  assert.throws(() => sm.transition(r, 'accept', 'customer'), /wrong-role/);
  const done = { status: 'price_set', customerId: 'c1', workerId: 'w1', agreedPrice: 100 };
  assert.throws(() => sm.transition(done, 'confirm_price', 'worker'), /wrong-role/);
  assert.throws(() => sm.transition(r, 'accept', null), /not-participant/);
});

test('invalid transitions are blocked', () => {
  const r = { status: 'new', customerId: 'c1', workerId: 'w1' };
  assert.throws(() => sm.transition(r, 'complete', 'worker'), /invalid-transition/);
  assert.throws(() => sm.transition(r, 'set_price', 'worker', { price: 100 }), /invalid-transition/);
  const cancelled = { ...r, status: 'cancelled' };
  assert.throws(() => sm.transition(cancelled, 'accept', 'worker'), /invalid-transition/);
  const completed = { ...r, status: 'completed' };
  assert.throws(() => sm.transition(completed, 'cancel', 'customer', { reason: 'other', note: 'xyz' }), /invalid-transition/);
});

test('time proposal flow', () => {
  let r = { status: 'new', customerId: 'c1', workerId: 'w1' };
  const t = Date.now() + 3600 * 1000;
  r = apply(r, 'propose_time', 'worker', { proposedAt: t });
  assert.equal(r.status, 'proposed');
  assert.equal(r.proposedAt, t);
  r = apply(r, 'accept_proposal', 'customer');
  assert.equal(r.status, 'confirmed');
  assert.equal(r.scheduledAt, t);
  assert.throws(() => sm.transition({ status: 'new' }, 'propose_time', 'worker', { proposedAt: 1 }), /invalid-time/);
});

test('cancel requires valid reason (and note for other)', () => {
  const r = { status: 'accepted', customerId: 'c1', workerId: 'w1' };
  assert.throws(() => sm.transition(r, 'cancel', 'customer', {}), /invalid-reason/);
  assert.throws(() => sm.transition(r, 'cancel', 'customer', { reason: 'too_far' }), /invalid-reason/);
  assert.throws(() => sm.transition(r, 'cancel', 'customer', { reason: 'other' }), /reason-note-required/);
  const ok = sm.transition(r, 'cancel', 'worker', { reason: 'too_far' });
  assert.equal(ok.to, 'cancelled');
  assert.equal(ok.patch.cancelledBy, 'worker');
  assert.equal(ok.patch.cancelReason, 'too_far');
});

test('price dispute sends job back to completed', () => {
  let r = { status: 'price_set', customerId: 'c1', workerId: 'w1', agreedPrice: 900 };
  r = apply(r, 'dispute_price', 'customer');
  assert.equal(r.status, 'completed');
  assert.equal(r.agreedPrice, null);
  r = apply(r, 'set_price', 'worker', { price: 700 });
  assert.equal(r.agreedPrice, 700);
});

test('price validation inside state machine', () => {
  const r = { status: 'completed' };
  for (const p of [0, -1, 'x', 5000000]) assert.throws(() => sm.transition(r, 'set_price', 'worker', { price: p }), /invalid-price/);
});

test('emergency/open request: eligible worker claims, others cannot act', () => {
  const r = { status: 'new', customerId: 'c1', workerId: null, open: true, isEmergency: true };
  assert.equal(sm.actorRole(r, 'w9', { isEligibleWorker: true }), 'open_worker');
  assert.equal(sm.actorRole(r, 'w9', { isEligibleWorker: false }), null);
  const t = sm.transition(r, 'accept', 'open_worker');
  assert.equal(t.to, 'accepted');
  assert.equal(t.meta.claimOpen, true);
  assert.throws(() => sm.transition(r, 'reject', 'open_worker'), /not-participant/);
  assert.throws(() => sm.transition(r, 'start', 'open_worker'), /not-participant/);
  // once claimed (status accepted) a second worker can no longer claim
  const claimed = { ...r, status: 'accepted', workerId: 'w9', open: false };
  assert.equal(sm.actorRole(claimed, 'w10', { isEligibleWorker: true }), null);
});

// ------------------------------------------------------------- Badges
test('badges follow rules', () => {
  const w = {
    verificationStatus: 'approved', idVerified: true, ratingAvg: 4.8, ratingCount: 12, completedCount: 60,
    stats: { received: 10, responded: 9, responseMinutesTotal: 45 },
  };
  assert.deepEqual(computeBadges(w), ['verified', 'top_rated', 'most_completed', 'fast_response']);
  assert.deepEqual(computeBadges({ ...w, idVerified: false, ratingCount: 3 }), ['most_completed', 'fast_response']);
  assert.deepEqual(computeBadges(w, { topRated: { enabled: false } }), ['verified', 'most_completed', 'fast_response']);
});

// ------------------------------------------------------------- Validation
test('Egyptian phone normalization', () => {
  assert.equal(v.normalizeEgPhone('+201012345678'), '01012345678');
  assert.equal(v.normalizeEgPhone('00201012345678'), '01012345678');
  assert.equal(v.normalizeEgPhone('٠١٠١٢٣٤٥٦٧٨'), '01012345678');
  assert.equal(v.mobile('+20 101 234 5678', 'p'), '01012345678');
  assert.throws(() => v.mobile('0301234567', 'p'), /invalid-phone/);
});

test('national id validation', () => {
  assert.equal(v.nationalId('29001011234567', 'id'), '29001011234567');
  assert.throws(() => v.nationalId('1234', 'id'), /invalid-national-id/);
});

test('arabic search tokens normalize letters', () => {
  const t = v.searchTokens('أحمد السبّاك');
  assert.ok(t.includes('احمد'));
  assert.ok(t.includes('الس'));
});

test('urlList accepts only Firebase Storage URLs', () => {
  assert.throws(() => v.urlList(['https://evil.com/x.png'], 'u'), /invalid-url/);
  assert.equal(v.urlList(['https://firebasestorage.googleapis.com/v0/b/x/o/a.png'], 'u').length, 1);
});

test('storage path prefix enforced', () => {
  assert.throws(() => v.storagePath('idDocs/other/x.jpg', 'p', 'idDocs/me/'), /invalid-path/);
  assert.throws(() => v.storagePath('idDocs/me/../x.jpg', 'p', 'idDocs/me/'), /invalid-path/);
});

// ------------------------------------------------------------- i18n
test('notifications localized with params', () => {
  const ar = render('price_confirmed', 'ar', { price: 500, commission: 25 });
  assert.match(ar.body, /500/);
  assert.match(ar.body, /25/);
  const en = render('nearby_request', 'en', { service: { ar: 'سباك', en: 'Plumber' }, km: '1.2' });
  assert.equal(en.body, 'Plumber request 1.2 km away');
});
