'use strict';
/**
 * In-memory fake of firebase-admin + firebase-functions (v2) — enough to run
 * the real Cloud Functions code end-to-end in tests without emulators.
 */
const Module = require('module');

// ---------------------------------------------------------------- Timestamp & FieldValue
class Timestamp {
  constructor(ms) { this._ms = ms; }
  static fromMillis(ms) { return new Timestamp(ms); }
  static fromDate(d) { return new Timestamp(d.getTime()); }
  static now() { return new Timestamp(Date.now()); }
  toMillis() { return this._ms; }
  toDate() { return new Date(this._ms); }
  valueOf() { return this._ms; }
}
class Transform { constructor(kind, value) { this.kind = kind; this.value = value; } }
const FieldValue = {
  serverTimestamp: () => new Transform('ts'),
  increment: (n) => new Transform('inc', n),
  arrayUnion: (...v) => new Transform('union', v),
  arrayRemove: (...v) => new Transform('remove', v),
  delete: () => new Transform('delete'),
};

const clone = (v) => (v instanceof Timestamp ? v : Array.isArray(v) ? v.map(clone) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, clone(x)])) : v);
const cmpVal = (v) => (v instanceof Timestamp ? v._ms : v instanceof Date ? v.getTime() : v);
const getPath = (obj, path) => path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);

function applyValue(cur, v) {
  if (v instanceof Transform) {
    switch (v.kind) {
      case 'ts': return Timestamp.now();
      case 'inc': return Math.round(((Number(cur) || 0) + v.value) * 1e6) / 1e6;
      case 'union': { const a = Array.isArray(cur) ? [...cur] : []; v.value.forEach((x) => { if (!a.includes(x)) a.push(x); }); return a; }
      case 'remove': return (Array.isArray(cur) ? cur : []).filter((x) => !v.value.includes(x));
      default: return undefined;
    }
  }
  return clone(v);
}
function setPath(obj, path, v) {
  const keys = path.split('.');
  let o = obj;
  for (let i = 0; i < keys.length - 1; i++) {
    if (typeof o[keys[i]] !== 'object' || o[keys[i]] === null) o[keys[i]] = {};
    o = o[keys[i]];
  }
  const last = keys[keys.length - 1];
  if (v instanceof Transform && v.kind === 'delete') { delete o[last]; return; }
  o[last] = applyValue(o[last], v);
}
function deepMerge(target, src) {
  for (const [k, v] of Object.entries(src)) {
    if (v && typeof v === 'object' && !(v instanceof Transform) && !(v instanceof Timestamp) && !Array.isArray(v)) {
      if (typeof target[k] !== 'object' || target[k] === null || Array.isArray(target[k])) target[k] = {};
      deepMerge(target[k], v);
    } else if (v instanceof Transform && v.kind === 'delete') delete target[k];
    else target[k] = applyValue(target[k], v);
  }
}

// ---------------------------------------------------------------- Firestore
class Snap {
  constructor(ref, data) { this.ref = ref; this.id = ref.id; this._d = data; this.exists = data !== undefined; }
  data() { return this._d === undefined ? undefined : clone(this._d); }
  get(f) { return getPath(this._d, f); }
}
class QuerySnap {
  constructor(docs) { this.docs = docs; this.size = docs.length; this.empty = docs.length === 0; }
  forEach(fn) { this.docs.forEach(fn); }
}

class FakeDb {
  constructor() { this.store = new Map(); this.triggers = []; this._id = 0; }
  doc(path) { return new DocRef(this, path); }
  collection(path) { return new Query(this, path); }
  batch() { return new Batch(this); }
  async runTransaction(fn) {
    // simple optimistic emulation: run once, apply writes at the end, reads must precede writes
    const tx = new Tx(this);
    const r = await fn(tx);
    await tx.commit();
    return r;
  }
  newId() { return 'id' + (++this._id).toString().padStart(6, '0') + Math.random().toString(36).slice(2, 10); }
  _write(path, data) {
    const existed = this.store.has(path);
    if (data === undefined) this.store.delete(path); else this.store.set(path, data);
    if (!existed && data !== undefined) this.triggers.forEach((t) => t(path, data));
  }
}

class DocRef {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split('/').pop(); }
  collection(name) { return new Query(this.db, `${this.path}/${name}`); }
  async get() { return new Snap(this, this.db.store.get(this.path)); }
  async set(data, opts = {}) {
    const cur = opts.merge ? clone(this.db.store.get(this.path) || {}) : {};
    deepMerge(cur, data);
    this.db._write(this.path, cur);
  }
  async update(data) {
    if (!this.db.store.has(this.path)) throw Object.assign(new Error(`NOT_FOUND: ${this.path}`), { code: 5 });
    const cur = clone(this.db.store.get(this.path));
    for (const [k, v] of Object.entries(data)) setPath(cur, k, v);
    this.db._write(this.path, cur);
  }
  async delete() { this.db._write(this.path, undefined); }
}

class Query {
  constructor(db, path, filters = [], order = null, start = null, end = null, lim = null, after = null) {
    Object.assign(this, { db, path, filters, order, start, end, lim, after });
    this.id = path.split('/').pop();
  }
  _clone(p) { return new Query(this.db, this.path, p.filters ?? this.filters, p.order ?? this.order, p.start ?? this.start, p.end ?? this.end, p.lim ?? this.lim, p.after ?? this.after); }
  doc(id) { return new DocRef(this.db, `${this.path}/${id || this.db.newId()}`); }
  async add(data) { const r = this.doc(); await r.set(data); return r; }
  where(f, op, v) { return this._clone({ filters: [...this.filters, [f, op, v]] }); }
  orderBy(f, dir = 'asc') { return this._clone({ order: [f, dir] }); }
  startAt(v) { return this._clone({ start: v }); }
  endAt(v) { return this._clone({ end: v }); }
  startAfter(snap) { return this._clone({ after: snap }); }
  limit(n) { return this._clone({ lim: n }); }
  async get() {
    const depth = this.path.split('/').length + 1;
    let docs = [...this.db.store.entries()]
      .filter(([p]) => p.startsWith(this.path + '/') && p.split('/').length === depth)
      .map(([p, d]) => new Snap(new DocRef(this.db, p), d));
    const val = (s, f) => (f === '__name__' ? s.id : getPath(s._d, f));
    for (const [f, op, v] of this.filters) {
      docs = docs.filter((s) => {
        const x = cmpVal(val(s, f)); const y = cmpVal(v);
        switch (op) {
          case '==': return x === y || (x === undefined && y === null);
          case '!=': return x !== y;
          case '>': return x !== undefined && x > y;
          case '>=': return x !== undefined && x >= y;
          case '<': return x !== undefined && x < y;
          case '<=': return x !== undefined && x <= y;
          case 'array-contains': return Array.isArray(x) && x.includes(v);
          case 'in': return v.includes(x);
          default: throw new Error('op ' + op);
        }
      });
    }
    if (this.order) {
      const [f, dir] = this.order;
      docs.sort((a, b) => { const x = cmpVal(val(a, f)); const y = cmpVal(val(b, f)); return (x > y ? 1 : x < y ? -1 : 0) * (dir === 'desc' ? -1 : 1); });
      if (this.start !== null) docs = docs.filter((s) => val(s, f) >= this.start);
      if (this.end !== null) docs = docs.filter((s) => val(s, f) <= this.end);
      if (this.after) { const i = docs.findIndex((s) => s.id === this.after.id); docs = docs.slice(i + 1); }
    }
    if (this.lim !== null) docs = docs.slice(0, this.lim);
    return new QuerySnap(docs);
  }
}

class Batch {
  constructor(db) { this.db = db; this.ops = []; }
  set(ref, data, opts) { this.ops.push(() => ref.set(data, opts)); return this; }
  update(ref, data) { this.ops.push(() => ref.update(data)); return this; }
  delete(ref) { this.ops.push(() => ref.delete()); return this; }
  async commit() { for (const op of this.ops) await op(); }
}
class Tx extends Batch {
  constructor(db) { super(db); this.wrote = false; }
  async get(refOrQuery) {
    if (this.ops.length) throw new Error('Firestore transactions require all reads before writes');
    return refOrQuery.get();
  }
}

// ---------------------------------------------------------------- Auth / Messaging / Storage
class FakeAuth {
  constructor() { this.users = new Map(); }
  _add(u) { this.users.set(u.uid, { customClaims: {}, providerData: [], disabled: false, ...u }); return this.users.get(u.uid); }
  async getUser(uid) { const u = this.users.get(uid); if (!u) throw Object.assign(new Error('nf'), { code: 'auth/user-not-found' }); return u; }
  async getUserByEmail(email) { for (const u of this.users.values()) if (u.email === email) return u; throw Object.assign(new Error('nf'), { code: 'auth/user-not-found' }); }
  async setCustomUserClaims(uid, c) { (await this.getUser(uid)).customClaims = c; }
  async updateUser(uid, p) { Object.assign(await this.getUser(uid), p); }
  async revokeRefreshTokens() {}
  async deleteUser(uid) { this.users.delete(uid); }
}
class FakeMessaging {
  constructor() { this.sent = []; }
  async sendEachForMulticast(m) { this.sent.push(m); return { responses: m.tokens.map(() => ({ success: true })) }; }
  async send(m) { this.sent.push(m); return 'msg'; }
}

// ---------------------------------------------------------------- install
function install() {
  const db = new FakeDb();
  const auth = new FakeAuth();
  const messaging = new FakeMessaging();
  const firestore = () => db;
  firestore.FieldValue = FieldValue;
  firestore.Timestamp = Timestamp;
  const adminMock = {
    apps: [],
    initializeApp() { this.apps.push({}); },
    firestore,
    auth: () => auth,
    messaging: () => messaging,
    storage: () => ({ bucket: () => ({ file: () => ({ setMetadata: async () => {} }) }) }),
  };
  class HttpsError extends Error {
    constructor(code, message, details) { super(message); this.code = code; this.details = details; }
  }
  const mocks = {
    'firebase-admin': adminMock,
    'firebase-functions/v2': { setGlobalOptions() {} },
    'firebase-functions/v2/https': { onCall: (h) => h, HttpsError },
    'firebase-functions/v2/firestore': { onDocumentCreated: (path, fn) => Object.assign(fn, { __path: path }) },
    'firebase-functions/v2/storage': { onObjectFinalized: (fn) => fn },
    'firebase-functions/v2/scheduler': { onSchedule: (o, fn) => fn },
  };
  const orig = Module._load;
  Module._load = function (request, ...rest) {
    if (Object.prototype.hasOwnProperty.call(mocks, request)) return mocks[request];
    return orig.call(this, request, ...rest);
  };
  return { db, auth, messaging, HttpsError, Timestamp, FieldValue };
}

module.exports = { install };
