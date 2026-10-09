// =============================================================
//  محتاج صنايعي — Web Admin Dashboard
//  Firebase JS SDK (modular) — كل العمليات الحساسة عبر Cloud Functions
// =============================================================
import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js';
import {
  getAuth, signInWithEmailAndPassword, onAuthStateChanged, signOut,
  createUserWithEmailAndPassword, sendEmailVerification, GoogleAuthProvider, signInWithPopup,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js';
import {
  getFirestore, collection, doc, getDoc, getDocs, query, where, orderBy, limit, setDoc, updateDoc, addDoc,
  serverTimestamp, getCountFromServer, getAggregateFromServer, sum, Timestamp, writeBatch, deleteDoc, increment,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js';
import { firebaseConfig, OWNER_EMAIL } from './config.js';

const fb = initializeApp(firebaseConfig);
const auth = getAuth(fb);
const db = getFirestore(fb);

let me = { uid: '', email: '', role: '' };

// ------------------------------------------------------------- helpers
const $ = (s, r = document) => r.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const loc = (v) => (v && typeof v === 'object' ? v.ar || v.en || '' : v || '');
const money = (n) => `${Number(n || 0).toLocaleString('en', { maximumFractionDigits: 2 })} ج`;
const toDate = (t) => (t && t.toDate ? t.toDate() : t ? new Date(t) : null);
const fmt = (t) => { const d = toDate(t); return d ? d.toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }) : '—'; };
const call = async (name, data) => ADMIN[name](data || {});
const can = (...roles) => me.role === 'super' || roles.includes(me.role);

function toast(msg, err = false) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast' + (err ? ' err' : '');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.classList.add('hidden'), 3500);
}
function errMsg(e) {
  const m = e?.message || String(e);
  const map = {
    'permission-denied': 'ليس لديك صلاحية', 'admin-only': 'للإدارة فقط', 'admin-role': 'صلاحيتك لا تسمح بهذه العملية',
    'has-outstanding-commission': 'على المستخدم عمولات مستحقة', 'already-reviewed': 'تمت مراجعتها بالفعل',
  };
  for (const k of Object.keys(map)) if (m.includes(k)) return map[k];
  return m;
}
async function run(btn, fn, okMsg = 'تم ✅') {
  if (btn) btn.disabled = true;
  try { await fn(); if (okMsg) toast(okMsg); } catch (e) { console.error(e); toast(errMsg(e), true); } finally { if (btn) btn.disabled = false; }
}
function openModal(html) { $('#modalBody').innerHTML = html; $('#modal').classList.remove('hidden'); }
function closeModal() { $('#modal').classList.add('hidden'); }
$('#modalClose').onclick = closeModal;
$('#modal').onclick = (e) => { if (e.target.id === 'modal') closeModal(); };

const STATUS = {
  new: ['طلب جديد', 'warn'], accepted: ['تم القبول', 'info'], rejected: ['مرفوض', 'bad'], proposed: ['موعد مقترح', 'warn'],
  confirmed: ['تم تأكيد الموعد', 'info'], on_the_way: ['في الطريق', 'info'], started: ['بدأ العمل', 'info'],
  completed: ['تم الانتهاء', 'purple'], price_set: ['بانتظار تأكيد السعر', 'purple'], price_agreed: ['تم الاتفاق على السعر', 'ok'],
  commission_paid: ['تم دفع العمولة', 'ok'], cancelled: ['ملغي', 'bad'],
};
const badge = (s, map = STATUS) => { const [t, c] = map[s] || [s, '']; return `<span class="badge ${c}">${esc(t)}</span>`; };
const REPORT_TYPES = { no_show: 'لم يحضر', bad_behavior: 'سوء معاملة', poor_quality: 'جودة سيئة', overcharge: 'مبالغة في السعر', fraud: 'احتيال', harassment: 'تحرش/تهديد', fake_account: 'حساب وهمي', payment_issue: 'مشكلة دفع', other: 'أخرى' };
const REPORT_STATUS = { new: ['جديد', 'warn'], reviewing: ['قيد المراجعة', 'info'], action_taken: ['تم اتخاذ إجراء', 'ok'], closed: ['مغلق', ''] };
const USER_STATUS = { active: ['نشط', 'ok'], suspended: ['موقوف', 'warn'], banned: ['محظور', 'bad'], deleted: ['محذوف', ''] };
const WORKER_STATUS = { pending: ['قيد المراجعة', 'warn'], approved: ['موثّق', 'ok'], rejected: ['مرفوض', 'bad'], deleted: ['محذوف', ''] };
const PAY_STATUS = { pending_review: ['قيد المراجعة', 'warn'], confirmed: ['مؤكد', 'ok'], rejected: ['مرفوض', 'bad'] };
const COM_STATUS = { due: ['مستحقة', 'warn'], claimed: ['قيد المراجعة', 'info'], paid: ['مدفوعة', 'ok'] };

// الصور مخزنة Base64 في media/{id} والمرجع "media:<id>"
async function imgFromPath(path) {
  if (!path) return '';
  if (!String(path).startsWith('media:')) return path;
  try {
    const d = await getDoc(doc(db, 'media', path.slice(6)));
    return d.exists() ? `data:${d.data().mime || 'image/jpeg'};base64,${d.data().data}` : '';
  } catch (e) { return ''; }
}
async function imgTag(src, cls = '') { const u = await imgFromPath(src); return u ? `<img class="${cls}" src="${u}" alt="">` : ''; }
const avg = (sum, count) => (count ? (sum / count) : 0);
const countOf = async (q) => (await getCountFromServer(q)).data().count;

let catalogCache = null;
async function catalog() {
  if (catalogCache) return catalogCache;
  const [c, s, l] = await Promise.all([getDocs(collection(db, 'categories')), getDocs(collection(db, 'services')), getDocs(collection(db, 'locations'))]);
  catalogCache = {
    cats: c.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => (a.order || 0) - (b.order || 0)),
    svcs: s.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => (a.order || 0) - (b.order || 0)),
    locs: l.docs.map((d) => ({ id: d.id, ...d.data() })),
  };
  return catalogCache;
}
const govName = (code) => catalogCache?.locs.find((l) => l.type === 'governorate' && l.code === code)?.nameAr || code || '';

// ------------------------------------------------------------- routing
const PAGES = [
  { id: 'dashboard', title: 'الإحصائيات', icon: '📊', roles: ['moderator', 'finance'] },
  { id: 'workers', title: 'الصنايعية', icon: '🔧', roles: ['moderator'] },
  { id: 'users', title: 'المستخدمون', icon: '👥', roles: ['moderator'] },
  { id: 'requests', title: 'الطلبات', icon: '📋', roles: ['moderator', 'finance'] },
  { id: 'finance', title: 'العمولات والمدفوعات', icon: '💳', roles: ['finance'] },
  { id: 'catalog', title: 'المهن والخدمات', icon: '🧰', roles: ['moderator'] },
  { id: 'locations', title: 'المناطق', icon: '📍', roles: ['moderator'] },
  { id: 'reports', title: 'الشكاوى والبلاغات', icon: '🚩', roles: ['moderator'] },
  { id: 'reviews', title: 'التقييمات', icon: '⭐', roles: ['moderator'] },
  { id: 'notify', title: 'الإشعارات', icon: '📣', roles: ['moderator'] },
  { id: 'support', title: 'الدعم', icon: '💬', roles: ['moderator'] },
  { id: 'settings', title: 'الإعدادات', icon: '⚙️', roles: ['finance'] },
  { id: 'admins', title: 'الإدارة والسجل', icon: '🛡️', roles: [] },
];

function buildNav() {
  $('#nav').innerHTML = PAGES.filter((p) => can(...p.roles))
    .map((p) => `<a href="#${p.id}" data-id="${p.id}">${p.icon} <span>${p.title}</span><span class="count hidden" id="cnt-${p.id}"></span></a>`).join('');
  refreshCounters();
}
async function refreshCounters() {
  const set = (id, n) => { const el = $(`#cnt-${id}`); if (!el) return; el.textContent = n; el.classList.toggle('hidden', !n); };
  try {
    if (can('moderator')) {
      set('workers', await countOf(query(collection(db, 'workers'), where('verificationStatus', '==', 'pending'))) +
        await countOf(query(collection(db, 'workerChangeRequests'), where('status', '==', 'pending'))));
      set('reports', await countOf(query(collection(db, 'reports'), where('status', '==', 'new'))));
      set('support', await countOf(query(collection(db, 'supportTickets'), where('status', '==', 'open'))));
    }
    if (can('finance')) set('finance', await countOf(query(collection(db, 'payments'), where('status', '==', 'pending_review'))));
  } catch (e) { console.warn(e); }
}

async function route() {
  const id = (location.hash || '#dashboard').slice(1).split('/')[0];
  const page = PAGES.find((p) => p.id === id && can(...p.roles)) || PAGES.find((p) => can(...p.roles));
  document.querySelectorAll('nav a').forEach((a) => a.classList.toggle('active', a.dataset.id === page.id));
  $('#pageTitle').textContent = page.title;
  $('#sidebar').classList.remove('open');
  const el = $('#page');
  el.innerHTML = '<div class="empty">جارٍ التحميل…</div>';
  try { await RENDER[page.id](el); } catch (e) { console.error(e); el.innerHTML = `<div class="card error">${esc(errMsg(e))}</div>`; }
}
window.addEventListener('hashchange', route);
$('#menuBtn').onclick = () => $('#sidebar').classList.toggle('open');

// ------------------------------------------------------------- auth
$('#loginForm').onsubmit = async (e) => {
  e.preventDefault();
  $('#loginError').textContent = '';
  try { await signInWithEmailAndPassword(auth, $('#email').value.trim(), $('#password').value); } catch (err) {
    $('#loginError').textContent = 'بيانات الدخول غير صحيحة';
  }
};
$('#logout').onclick = () => signOut(auth);

// صاحب التطبيق: إنشاء الحساب لأول مرة (بريد + كلمة سر) ثم تأكيد البريد من Gmail
$('#ownerSignup').onclick = async () => {
  $('#loginError').textContent = ''; $('#loginInfo').textContent = '';
  const email = $('#email').value.trim(); const pass = $('#password').value;
  if (!email || pass.length < 8) { $('#loginError').textContent = 'اكتب البريد وكلمة سر (8 حروف على الأقل) ثم اضغط الزر'; return; }
  try {
    const cred = await createUserWithEmailAndPassword(auth, email, pass);
    await sendEmailVerification(cred.user);
    $('#loginInfo').textContent = '✅ تم إنشاء الحساب. افتح بريدك (وفولدر Spam) واضغط رابط التأكيد، ثم ارجع هنا واضغط "دخول".';
    await signOut(auth);
  } catch (e) {
    $('#loginError').textContent = e.code === 'auth/email-already-in-use' ? 'الحساب موجود بالفعل — اضغط "دخول"' : 'تعذر إنشاء الحساب: ' + (e.code || e.message);
  }
};
$('#googleBtn').onclick = async () => {
  $('#loginError').textContent = '';
  try { await signInWithPopup(auth, new GoogleAuthProvider()); } catch (e) { $('#loginError').textContent = 'تعذر الدخول بـ Google'; }
};

onAuthStateChanged(auth, async (u) => {
  if (!u) { $('#app').classList.add('hidden'); $('#login').classList.remove('hidden'); return; }
  let adm = await getDoc(doc(db, 'admins', u.uid)).catch(() => null);
  if (!adm || !adm.exists()) {
    // صاحب التطبيق يحصل على صلاحية المدير العام تلقائيًا بعد تأكيد بريده
    if ((u.email || '').toLowerCase() === OWNER_EMAIL) {
      await u.reload();
      if (!auth.currentUser.emailVerified) {
        try { await sendEmailVerification(auth.currentUser); } catch (_) { /* rate limited */ }
        $('#loginError').textContent = 'لازم تأكد بريدك الأول — بعتنالك رابط تأكيد على الإيميل (شوف Spam كمان)، اضغطه ثم ادخل تاني';
        await signOut(auth);
        return;
      }
      await auth.currentUser.getIdToken(true);
      try {
        await setDoc(doc(db, 'admins', u.uid), { email: OWNER_EMAIL, role: 'super', active: true, owner: true, createdAt: serverTimestamp() });
        adm = await getDoc(doc(db, 'admins', u.uid));
      } catch (e) { console.error(e); }
    } else {
      // أي حساب تاني: طلب صلاحية يوافق عليه المدير العام
      try { await setDoc(doc(db, 'adminRequests', u.uid), { email: (u.email || '').toLowerCase(), createdAt: serverTimestamp() }); } catch (_) {}
    }
  }
  if (!adm || !adm.exists() || adm.data().active !== true) {
    $('#loginError').textContent = 'هذا الحساب ليس له صلاحية إدارة — تم إرسال طلب صلاحية للمدير العام';
    await signOut(auth);
    return;
  }
  const a = adm.data();
  me = { uid: u.uid, email: u.email, role: a.role || 'moderator', demo: a.demo === true };
  $('#meEmail').textContent = me.email;
  $('#meRole').textContent = { super: 'مدير عام', moderator: 'مشرف', finance: 'مالية' }[me.role] || me.role;
  $('#demoBadge').classList.toggle('hidden', !me.demo);
  $('#login').classList.add('hidden');
  $('#app').classList.remove('hidden');
  await catalog().catch(() => null);
  buildNav();
  route();
});

// =============================================================
//  عمليات الإدارة (الخطة المجانية — كتابة مباشرة محمية بقواعد الأمان)
// =============================================================
const now = () => serverTimestamp();
async function logAction(action, targetType, targetId, details = {}) {
  try { await addDoc(collection(db, 'adminActions'), { adminId: me.uid, adminEmail: me.email, action, targetType, targetId, details, createdAt: now() }); } catch (_) {}
}
async function notifyUser(uid, type, params = {}, data = {}) {
  if (!uid) return;
  try { await addDoc(collection(db, `notifications/${uid}/items`), { type, params, data, read: false, fromUid: me.uid, createdAt: now() }); } catch (_) {}
}
const ADMIN = {
  async adminGetWorkerPrivate({ workerId }) {
    const p = await getDoc(doc(db, 'workerPrivate', workerId));
    const d = p.exists() ? p.data() : {};
    await logAction('view_identity', 'worker', workerId);
    const ch = await getDocs(query(collection(db, 'workerChangeRequests'), where('workerId', '==', workerId), where('status', '==', 'pending')));
    const pendingIdentity = ch.docs.map((x) => x.data().identity).find(Boolean);
    return {
      exists: p.exists(), idNumber: d.nationalId || '', idFrontPath: d.idFrontRef || '', idBackPath: d.idBackRef || '',
      pending: pendingIdentity ? { idNumber: pendingIdentity.nationalId, idFrontPath: pendingIdentity.idFrontRef, idBackPath: pendingIdentity.idBackRef || '' } : null,
    };
  },
  async adminReviewWorker({ workerId, decision, reason, idVerified }) {
    const w = (await getDoc(doc(db, 'workers', workerId))).data();
    const patch = {
      verificationStatus: decision === 'approve' ? 'approved' : decision === 'reject' ? 'rejected' : 'pending',
      rejectionReason: decision === 'reject' ? reason : '',
      idVerified: decision === 'approve' ? (idVerified === true && w.hasIdDoc === true) : false,
      reviewedAt: now(), reviewedBy: me.uid,
    };
    if (decision === 'approve' && !w.approvedAt) patch.approvedAt = now();
    await updateDoc(doc(db, 'workers', workerId), patch);
    await logAction(`worker_${decision}`, 'worker', workerId, { reason });
    if (decision === 'approve') await notifyUser(workerId, 'account_approved');
    if (decision === 'reject') await notifyUser(workerId, 'account_rejected', { reason });
  },
  async adminReviewChange({ changeId, decision, reason, idVerified }) {
    const cRef = doc(db, 'workerChangeRequests', changeId);
    const c = (await getDoc(cRef)).data();
    const wRef = doc(db, 'workers', c.workerId);
    const b = writeBatch(db);
    if (decision === 'approve') {
      const cat = await catalog();
      const cur = (await getDoc(wRef)).data();
      const ch = c.changes || {};
      const patch = { pendingChange: false, updatedAt: now() };
      if (ch.name) patch.name = ch.name;
      const cats = ch.categoryIds || cur.categoryIds; const svcs = ch.serviceIds || cur.serviceIds;
      if (ch.categoryIds || ch.serviceIds) {
        patch.categoryIds = cats; patch.serviceIds = svcs;
        patch.categoryNames = cats.map((id) => cat.cats.find((x) => x.id === id)).filter(Boolean).map((x) => ({ ar: x.nameAr, en: x.nameEn }));
        patch.serviceNames = svcs.map((id) => cat.svcs.find((x) => x.id === id)).filter(Boolean).map((x) => ({ ar: x.nameAr, en: x.nameEn }));
      }
      if (ch.name || ch.categoryIds) {
        const names = (patch.categoryNames || cur.categoryNames || []).flatMap((n) => [n.ar, n.en]);
        patch.searchTokens = tokens([patch.name || cur.name, ...names]);
      }
      if (c.identity) {
        const priv = (await getDoc(doc(db, 'workerPrivate', c.workerId))).data() || {};
        if (priv.nationalId && priv.nationalId !== c.identity.nationalId) b.delete(doc(db, 'nationalIds', priv.nationalId));
        b.set(doc(db, 'nationalIds', c.identity.nationalId), { uid: c.workerId, createdAt: now() });
        b.set(doc(db, 'workerPrivate', c.workerId), { nationalId: c.identity.nationalId, idFrontRef: c.identity.idFrontRef || '', idBackRef: c.identity.idBackRef || '', updatedAt: now() }, { merge: true });
        patch.hasIdDoc = true; patch.idVerified = idVerified === true;
      }
      b.update(wRef, patch);
    } else {
      b.update(wRef, { pendingChange: false });
    }
    b.update(cRef, { status: decision === 'approve' ? 'approved' : 'rejected', reason: reason || '', reviewedBy: me.uid, reviewedAt: now() });
    await b.commit();
    await logAction(`change_${decision}`, 'worker', c.workerId, { changeId, reason });
    await notifyUser(c.workerId, decision === 'approve' ? 'change_approved' : 'change_rejected', { reason: reason || '' });
  },
  async adminSetUserStatus({ uid, status, reason, until }) {
    const b = writeBatch(db);
    b.update(doc(db, 'users', uid), { status, statusReason: reason || '', bannedUntil: status === 'banned' && until ? Timestamp.fromMillis(until) : null, statusUpdatedAt: now() });
    const w = await getDoc(doc(db, 'workers', uid));
    if (w.exists()) b.update(doc(db, 'workers', uid), { suspended: status !== 'active' });
    await b.commit();
    await logAction(`user_${status}`, 'user', uid, { reason });
  },
  async adminUpdateUser({ uid, name, adminNote }) {
    await updateDoc(doc(db, 'users', uid), { name, adminNote: adminNote || '' });
    const w = await getDoc(doc(db, 'workers', uid));
    if (w.exists() && name) await updateDoc(doc(db, 'workers', uid), { name });
    await logAction('user_update', 'user', uid, { name });
  },
  async adminDeleteUser({ uid, reason }) {
    // الخطة المجانية: الحساب يتقفل نهائيًا وتتمسح بياناته الشخصية (حذف حساب الدخول من Firebase Console → Authentication)
    const b = writeBatch(db);
    b.update(doc(db, 'users', uid), { status: 'deleted', name: 'Deleted user', photoUrl: '', email: '', statusReason: reason, deletedAt: now() });
    const w = await getDoc(doc(db, 'workers', uid));
    if (w.exists()) b.update(doc(db, 'workers', uid), { suspended: true, verificationStatus: 'deleted', name: 'Deleted', photoUrl: '', bio: '', whatsapp: '', callPhone: '', workImages: [], searchTokens: [] });
    await b.commit();
    await logAction('user_delete', 'user', uid, { reason });
  },
  async adminReviewPayment({ paymentId, decision, note }) {
    const pRef = doc(db, 'payments', paymentId);
    const p = (await getDoc(pRef)).data();
    if (p.status !== 'pending_review') throw new Error('already-reviewed');
    const b = writeBatch(db);
    b.update(pRef, { status: decision === 'confirm' ? 'confirmed' : 'rejected', reviewNote: note || '', reviewedBy: me.uid, reviewedAt: now() });
    for (const cid of p.commissionIds) {
      if (decision === 'confirm') {
        b.update(doc(db, 'commissions', cid), { status: 'paid', paidAt: now() });
        const r = await getDoc(doc(db, 'requests', cid));
        if (r.exists()) {
          const upd = { commissionStatus: 'paid', updatedAt: now() };
          if (r.data().status === 'price_agreed') upd.status = 'commission_paid';
          b.update(r.ref, upd);
          b.set(doc(collection(db, `requests/${cid}/history`)), { from: r.data().status, to: upd.status || r.data().status, action: 'commission_paid', by: 'admin', byUid: me.uid, note: paymentId, at: now() });
        }
      } else {
        b.update(doc(db, 'commissions', cid), { status: 'due', paymentId: null });
      }
    }
    await b.commit();
    await logAction(`payment_${decision}`, 'payment', paymentId, { amount: p.amount, workerId: p.workerId, note });
    await notifyUser(p.workerId, decision === 'confirm' ? 'payment_confirmed' : 'payment_rejected', { amount: p.amount, reason: note || '' });
  },
  async adminUpdateSettings(patch) {
    if (patch.commissionRate !== undefined) {
      const r = Number(patch.commissionRate);
      if (!(r >= 0 && r <= 0.3)) throw new Error('نسبة العمولة لازم تكون بين 0% و 30%');
      patch.commissionRate = Math.round(r * 10000) / 10000;
    }
    await setDoc(doc(db, 'settings', 'public'), { ...patch, updatedAt: now(), updatedBy: me.uid }, { merge: true });
    await logAction('settings_update', 'settings', 'public', patch);
  },
  async adminSetReviewHidden({ reviewId, hidden }) {
    const rRef = doc(db, 'reviews', reviewId);
    const rv = (await getDoc(rRef)).data();
    await updateDoc(rRef, { hidden, moderatedBy: me.uid, moderatedAt: now() });
    if (rv.direction === 'c2w') {
      const all = await getDocs(query(collection(db, 'reviews'), where('toId', '==', rv.toId), where('direction', '==', 'c2w'), where('hidden', '==', false)));
      let total = 0; all.forEach((d) => { total += Number(d.data().stars || 0); });
      await updateDoc(doc(db, 'workers', rv.toId), { ratingSum: total, ratingCount: all.size });
    }
    await logAction(hidden ? 'review_hide' : 'review_show', 'review', reviewId);
  },
  async adminUpdateReport({ reportId, status, adminNote, actionTaken, category }) {
    const rRef = doc(db, 'reports', reportId);
    const r = (await getDoc(rRef)).data();
    await updateDoc(rRef, { status, adminNote: adminNote || '', actionTaken: actionTaken || '', ...(category ? { category } : {}), handledBy: me.uid, updatedAt: now() });
    await logAction('report_update', 'report', reportId, { status, actionTaken });
    const st = { new: { ar: 'جديد', en: 'New' }, reviewing: { ar: 'قيد المراجعة', en: 'Under review' }, action_taken: { ar: 'تم اتخاذ إجراء', en: 'Action taken' }, closed: { ar: 'مغلق', en: 'Closed' } }[status];
    await notifyUser(r.reporterId, 'report_update', { status: st });
  },
  async adminBroadcast({ target, value, titleAr, bodyAr, titleEn, bodyEn }) {
    if (!titleAr || !bodyAr) throw new Error('اكتب العنوان والنص بالعربي');
    let v = value || '';
    if (target === 'user' && /^(\+?20|0)1\d{9}$/.test(v)) v = v.replace(/^\+?20/, '0');
    await addDoc(collection(db, 'broadcasts'), { target, value: v, titleAr, bodyAr, titleEn: titleEn || titleAr, bodyEn: bodyEn || bodyAr, sentBy: me.uid, createdAt: now() });
    await logAction('broadcast', 'notification', target, { value: v, titleAr });
  },
  async adminSetAdminRole({ uid, email, role }) {
    if (uid === me.uid && role !== 'super') throw new Error('مينفعش تشيل صلاحيتك بنفسك');
    if (role === 'none') await deleteDoc(doc(db, 'admins', uid));
    else await setDoc(doc(db, 'admins', uid), { email, role, active: true, updatedAt: now(), updatedBy: me.uid }, { merge: true });
    await deleteDoc(doc(db, 'adminRequests', uid)).catch(() => {});
    await logAction('admin_role', 'admin', uid, { email, role });
  },
};
function tokens(texts) {
  const norm = (x) => String(x || '').toLowerCase().replace(/[\u064B-\u0652\u0640]/g, '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
  const out = new Set();
  for (const t of texts) for (const w of norm(t).split(/[\s,.-]+/).filter(Boolean)) for (let i = 2; i <= Math.min(w.length, 15); i++) out.add(w.slice(0, i));
  return [...out].slice(0, 200);
}

// =============================================================
//  الصفحات
// =============================================================
const RENDER = {};

// ------------------------------------------------------------- 📊 الإحصائيات
RENDER.dashboard = async (el) => {
  const iso = (d) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' }).format(d);
  const from30 = new Date(Date.now() - 29 * 86400000);
  el.innerHTML = `
    <div class="card row">
      <label>من <input type="date" id="dFrom" value="${iso(from30)}"></label>
      <label>إلى <input type="date" id="dTo" value="${iso(new Date())}"></label>
      <button class="btn primary" id="dApply">عرض</button>
    </div>
    <div class="grid kpis" id="kpis"><div class="empty">…</div></div>
    <div class="grid two">
      <div class="card"><h3>الطلبات يوميًا (الفترة)</h3><canvas id="chReq"></canvas></div>
      <div class="card"><h3>عمولة التطبيق يوميًا (ج)</h3><canvas id="chCom"></canvas></div>
      <div class="card"><h3>أكثر المهن طلبًا (الفترة)</h3><canvas id="chCat"></canvas></div>
      <div class="card"><h3>أكثر المحافظات نشاطًا (الفترة)</h3><canvas id="chGov"></canvas></div>
    </div>`;
  const cnt = (q) => countOf(q);
  const C = (name) => collection(db, name);
  const [customers, workers, approved, pending, totalReq, completedReq, cancelledReq, activeReq] = await Promise.all([
    cnt(query(C('users'), where('role', '==', 'customer'))),
    cnt(query(C('users'), where('role', '==', 'worker'))),
    cnt(query(C('workers'), where('verificationStatus', '==', 'approved'))),
    cnt(query(C('workers'), where('verificationStatus', '==', 'pending'))),
    cnt(C('requests')),
    cnt(query(C('requests'), where('status', 'in', ['price_agreed', 'commission_paid']))),
    cnt(query(C('requests'), where('status', '==', 'cancelled'))),
    cnt(query(C('requests'), where('status', 'in', ['new', 'accepted', 'proposed', 'confirmed', 'on_the_way', 'started', 'completed', 'price_set']))),
  ]);
  // متوسط التقييمات من مجاميع التقييم
  const [wSum, wCnt, cSum, cCnt] = await Promise.all([
    getAggregateFromServer(C('workers'), { s: sum('ratingSum') }).then((x) => x.data().s || 0).catch(() => 0),
    getAggregateFromServer(C('workers'), { s: sum('ratingCount') }).then((x) => x.data().s || 0).catch(() => 0),
    getAggregateFromServer(C('users'), { s: sum('customerRatingSum') }).then((x) => x.data().s || 0).catch(() => 0),
    getAggregateFromServer(C('users'), { s: sum('customerRatingCount') }).then((x) => x.data().s || 0).catch(() => 0),
  ]);
  const comSum = async (fromDate) => { try { return (await getAggregateFromServer(query(C('commissions'), where('createdAt', '>=', Timestamp.fromDate(fromDate))), { s: sum('amount') })).data().s || 0; } catch (e) { console.warn(e); return 0; } };
  const startOfToday = new Date(new Date().toLocaleString('en-US', { timeZone: 'Africa/Cairo' })); startOfToday.setHours(0, 0, 0, 0);
  const monthStart = new Date(startOfToday); monthStart.setDate(1);
  const [pToday, pWeek, pMonth] = await Promise.all([comSum(startOfToday), comSum(new Date(Date.now() - 7 * 86400000)), comSum(monthStart)]);

  const charts = [];
  async function loadRange() {
    charts.forEach((c) => c.destroy()); charts.length = 0;
    const from = new Date($('#dFrom').value + 'T00:00:00'); const to = new Date($('#dTo').value + 'T23:59:59');
    const [reqs, coms] = await Promise.all([
      getDocs(query(C('requests'), where('createdAt', '>=', Timestamp.fromDate(from)), where('createdAt', '<=', Timestamp.fromDate(to)), orderBy('createdAt', 'desc'), limit(3000))),
      getDocs(query(C('commissions'), where('createdAt', '>=', Timestamp.fromDate(from)), where('createdAt', '<=', Timestamp.fromDate(to)), orderBy('createdAt', 'desc'), limit(3000))),
    ]);
    const days = {}; const key = (t) => iso(t.toDate());
    for (let d = new Date(from); d <= to; d = new Date(d.getTime() + 86400000)) days[iso(d)] = { requests: 0, completed: 0, cancelled: 0, commission: 0, services: 0 };
    const byCat = {}; const byGov = {}; let emergencies = 0;
    reqs.forEach((x) => {
      const r = x.data(); if (!r.createdAt) return; const k = key(r.createdAt); if (!days[k]) return;
      days[k].requests++;
      if (['price_agreed', 'commission_paid'].includes(r.status)) days[k].completed++;
      if (r.status === 'cancelled') days[k].cancelled++;
      if (r.isEmergency) emergencies++;
      byCat[r.categoryId] = (byCat[r.categoryId] || 0) + 1;
      const g = r.location?.governorate; if (g) byGov[g] = (byGov[g] || 0) + 1;
    });
    let rangeCom = 0; let rangeSvc = 0;
    coms.forEach((x) => { const c = x.data(); if (!c.createdAt) return; const k = key(c.createdAt); rangeCom += c.amount || 0; rangeSvc += c.servicePrice || 0; if (days[k]) { days[k].commission += c.amount || 0; } });
    const kpi = (l, v) => `<div class="kpi"><div class="v">${v}</div><div class="l">${l}</div></div>`;
    $('#kpis').innerHTML = [
      kpi('إجمالي العملاء', customers), kpi('إجمالي الصنايعية', workers), kpi('الصنايعية الموثقون', approved),
      kpi('حسابات قيد المراجعة', pending), kpi('إجمالي الطلبات', totalReq), kpi('الطلبات المكتملة', completedReq),
      kpi('الطلبات الملغاة', cancelledReq), kpi('الطلبات الحالية', activeReq),
      kpi('قيمة الخدمات (الفترة)', money(rangeSvc)), kpi('عمولة التطبيق (الفترة)', money(rangeCom)),
      kpi('أرباح اليوم', money(pToday)), kpi('أرباح آخر 7 أيام', money(pWeek)), kpi('أرباح الشهر', money(pMonth)),
      kpi('متوسط تقييم الصنايعية', wCnt ? (wSum / wCnt).toFixed(2) + ' ★' : '—'), kpi('متوسط تقييم العملاء', cCnt ? (cSum / cCnt).toFixed(2) + ' ★' : '—'),
      kpi('معدل الإتمام', totalReq ? Math.round((completedReq / totalReq) * 100) + '%' : '—'),
      kpi('معدل الإلغاء', totalReq ? Math.round((cancelledReq / totalReq) * 100) + '%' : '—'),
      kpi('طلبات الفترة', reqs.size), kpi('طوارئ الفترة', emergencies),
    ].join('');
    const labels = Object.keys(days).map((d) => d.slice(5)); const vals = Object.values(days);
    const navy = '#12355B'; const amber = '#F59E0B';
    charts.push(new Chart($('#chReq'), { type: 'bar', data: { labels, datasets: [
      { label: 'طلبات', data: vals.map((d) => d.requests), backgroundColor: navy },
      { label: 'مكتملة', data: vals.map((d) => d.completed), backgroundColor: '#16A34A' },
      { label: 'ملغاة', data: vals.map((d) => d.cancelled), backgroundColor: '#DC2626' },
    ] }, options: { responsive: true, plugins: { legend: { position: 'bottom' } } } }));
    charts.push(new Chart($('#chCom'), { type: 'line', data: { labels, datasets: [
      { label: 'العمولة', data: vals.map((d) => Math.round(d.commission * 100) / 100), borderColor: amber, backgroundColor: 'rgba(245,158,11,.15)', fill: true, tension: .3 },
    ] }, options: { plugins: { legend: { display: false } } } }));
    const top = (m) => Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 8);
    const cats = top(byCat);
    charts.push(new Chart($('#chCat'), { type: 'bar', data: { labels: cats.map(([k]) => catalogCache?.cats.find((c) => c.id === k)?.nameAr || k), datasets: [{ data: cats.map(([, v]) => v), backgroundColor: amber }] }, options: { indexAxis: 'y', plugins: { legend: { display: false } } } }));
    const govs = top(byGov);
    charts.push(new Chart($('#chGov'), { type: 'bar', data: { labels: govs.map(([k]) => govName(k)), datasets: [{ data: govs.map(([, v]) => v), backgroundColor: navy }] }, options: { indexAxis: 'y', plugins: { legend: { display: false } } } }));
  }
  $('#dApply').onclick = () => run($('#dApply'), loadRange, null);
  await loadRange();
};

// ------------------------------------------------------------- 🔧 الصنايعية
RENDER.workers = async (el) => {
  el.innerHTML = `
    <div class="card row">
      <select id="wStatus"><option value="pending">قيد المراجعة</option><option value="approved">موثّق</option><option value="rejected">مرفوض</option></select>
      <button class="btn" id="wChanges">تعديلات بانتظار المراجعة</button>
    </div>
    <div class="card"><div class="table-wrap" id="wTable"></div></div>`;
  const load = async () => {
    const st = $('#wStatus').value;
    const snap = await getDocs(query(collection(db, 'workers'), where('verificationStatus', '==', st), orderBy('submittedAt', 'desc'), limit(200)));
    $('#wTable').innerHTML = snap.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>الاسم</th><th>الهاتف</th><th>المهنة</th><th>المحافظة</th><th>بطاقة</th><th>التقييم</th><th>تاريخ التقديم</th><th></th></tr>
      ${snap.docs.map((d) => { const w = d.data(); return `<tr>
        <td><b>${esc(w.name)}</b> ${w.suspended ? '<span class="badge bad">موقوف</span>' : ''}${w.pendingChange ? ' <span class="badge info">تعديل معلق</span>' : ''}</td>
        <td dir="ltr">${esc(w.phone)}</td><td>${esc((w.categoryNames || []).map(loc).join('، '))}</td>
        <td>${esc(govName(w.governorate))} - ${esc(w.city)}</td>
        <td>${w.hasIdDoc ? (w.idVerified ? '<span class="badge ok">موثّقة</span>' : '<span class="badge warn">مرفوعة</span>') : '<span class="badge">لا</span>'}</td>
        <td>${w.ratingCount ? `${avg(w.ratingSum, w.ratingCount).toFixed(1)} ★ (${w.ratingCount})` : '—'}</td><td>${fmt(w.submittedAt)}</td>
        <td><button class="btn small primary" data-w="${d.id}">مراجعة</button></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-w]').forEach((b) => b.onclick = () => reviewWorker(b.dataset.w, load));
  };
  $('#wStatus').onchange = load;
  $('#wChanges').onclick = () => changeRequests();
  await load();
};

async function reviewWorker(id, reload) {
  const w = (await getDoc(doc(db, 'workers', id))).data();
  let priv = { exists: false };
  try { priv = await call('adminGetWorkerPrivate', { workerId: id }); } catch (e) { console.warn(e); }
  const [front, back] = await Promise.all([imgFromPath(priv.idFrontPath), imgFromPath(priv.idBackPath)]);
  openModal(`
    <h3>${esc(w.name)} ${badge(w.verificationStatus, WORKER_STATUS)}</h3>
    <div class="kv">
      <div>الهاتف</div><div dir="ltr">${esc(w.phone)}</div>
      <div>واتساب / اتصال</div><div dir="ltr">${esc(w.whatsapp)} / ${esc(w.callPhone)}</div>
      <div>المهن</div><div>${esc((w.categoryNames || []).map(loc).join('، '))}</div>
      <div>الخدمات</div><div>${esc((w.serviceNames || []).map(loc).join('، ')) || '—'}</div>
      <div>الموقع</div><div>${esc(govName(w.governorate))} - ${esc(w.city)} - ${esc(w.area)} — <a target="_blank" rel="noopener" href="https://www.google.com/maps?q=${w.geo?.lat},${w.geo?.lng}">خريطة</a></div>
      <div>سعر الكشف</div><div>${w.visitFee == null ? '—' : money(w.visitFee)}</div>
      <div>النبذة</div><div>${esc(w.bio) || '—'}</div>
      <div>الرقم القومي</div><div dir="ltr">${priv.idNumber ? esc(priv.idNumber) : '—'}</div>
    </div>
    ${w.photoUrl ? `<h4>الصورة الشخصية</h4><div class="thumbs">${await imgTag(w.photoUrl)}</div>` : ''}
    ${(front || back) ? `<h4>البطاقة الشخصية (سرية — لا تُشارك)</h4><div class="grid two">${front ? `<img class="id-img" src="${front}">` : ''}${back ? `<img class="id-img" src="${back}">` : ''}</div>` : '<p class="muted">لم يرفع بطاقة</p>'}
    ${(w.workImages || []).length ? `<h4>أعمال سابقة</h4><div class="thumbs">${(await Promise.all(w.workImages.map((u) => imgTag(u)))).join('')}</div>` : ''}
    <hr>
    <label><span><input type="checkbox" id="idVer" ${w.idVerified ? 'checked' : ''} ${w.hasIdDoc ? '' : 'disabled'} style="width:auto"> البطاقة مطابقة (يحصل على علامة موثّق)</span></label>
    <label>سبب الرفض (مطلوب عند الرفض)<input id="rejReason" value="${esc(w.rejectionReason || '')}"></label>
    <div class="row" style="margin-top:12px">
      <button class="btn success" id="apprBtn">قبول وتوثيق</button>
      <button class="btn danger" id="rejBtn">رفض</button>
      <button class="btn" id="pendBtn">إعادة للمراجعة</button>
    </div>`);
  const act = (decision, btn) => run(btn, async () => {
    await call('adminReviewWorker', { workerId: id, decision, reason: $('#rejReason').value.trim(), idVerified: $('#idVer').checked });
    closeModal(); reload(); refreshCounters();
  });
  $('#apprBtn').onclick = (e) => act('approve', e.target);
  $('#rejBtn').onclick = (e) => { if (!$('#rejReason').value.trim()) return toast('اكتب سبب الرفض', true); act('reject', e.target); };
  $('#pendBtn').onclick = (e) => act('pending', e.target);
}

async function changeRequests() {
  const snap = await getDocs(query(collection(db, 'workerChangeRequests'), where('status', '==', 'pending'), orderBy('createdAt', 'desc'), limit(100)));
  const cat = await catalog();
  const name = (id, list) => list.find((x) => x.id === id)?.nameAr || id;
  openModal(`<h3>تعديلات بيانات حساسة بانتظار المراجعة</h3>${snap.empty ? '<div class="empty">لا يوجد</div>' : snap.docs.map((d) => {
    const c = d.data(); const ch = c.changes || {};
    return `<div class="card" style="margin-bottom:10px"><b>${esc(c.workerName)}</b> — ${fmt(c.createdAt)}
      <div class="kv" style="margin-top:8px">
        ${ch.name ? `<div>الاسم الجديد</div><div>${esc(ch.name)}</div>` : ''}
        ${ch.categoryIds ? `<div>المهن الجديدة</div><div>${esc(ch.categoryIds.map((x) => name(x, cat.cats)).join('، '))}</div>` : ''}
        ${ch.serviceIds ? `<div>الخدمات الجديدة</div><div>${esc(ch.serviceIds.map((x) => name(x, cat.svcs)).join('، '))}</div>` : ''}
        ${c.identity ? `<div>هوية جديدة</div><div>رقم ينتهي بـ ${esc(c.identity.idLast4)} — <button class="btn small" data-idv="${c.workerId}">عرض</button></div>` : ''}
      </div>
      <div class="row" style="margin-top:8px"><input placeholder="سبب الرفض" id="r-${d.id}">
      ${c.identity ? `<label style="display:inline"><input type="checkbox" id="v-${d.id}" style="width:auto"> الهوية مطابقة</label>` : ''}
      <button class="btn success small" data-ok="${d.id}">اعتماد</button><button class="btn danger small" data-no="${d.id}">رفض</button></div></div>`;
  }).join('')}`);
  document.querySelectorAll('[data-ok]').forEach((b) => b.onclick = () => run(b, async () => {
    await call('adminReviewChange', { changeId: b.dataset.ok, decision: 'approve', idVerified: $(`#v-${b.dataset.ok}`)?.checked === true });
    b.closest('.card').remove(); refreshCounters();
  }));
  document.querySelectorAll('[data-no]').forEach((b) => b.onclick = () => run(b, async () => {
    const reason = $(`#r-${b.dataset.no}`).value.trim(); if (!reason) throw new Error('اكتب سبب الرفض');
    await call('adminReviewChange', { changeId: b.dataset.no, decision: 'reject', reason });
    b.closest('.card').remove(); refreshCounters();
  }));
  document.querySelectorAll('[data-idv]').forEach((b) => b.onclick = async () => {
    const p = await call('adminGetWorkerPrivate', { workerId: b.dataset.idv });
    if (!p.pending) return;
    const img = await imgFromPath(p.pending.idFrontPath);
    b.outerHTML = `<span dir="ltr">${esc(p.pending.idNumber)}</span>${img ? `<br><img class="id-img" src="${img}">` : ''}`;
  });
}

// ------------------------------------------------------------- 👥 المستخدمون
RENDER.users = async (el) => {
  el.innerHTML = `
    <div class="card row">
      <select id="uRole"><option value="customer">العملاء</option><option value="worker">الصنايعية</option></select>
      <input id="uPhone" placeholder="بحث برقم الموبايل 01xxxxxxxxx" dir="ltr">
      <button class="btn primary" id="uSearch">بحث</button>
      <button class="btn" id="uAlerts">تنبيهات الحسابات المشبوهة</button>
    </div>
    <div class="card"><div class="table-wrap" id="uTable"></div></div>`;
  const render = (docs) => {
    $('#uTable').innerHTML = !docs.length ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>الاسم</th><th>الهاتف</th><th>النوع</th><th>الحالة</th><th>تقييم كعميل</th><th>بلاغات ضده</th><th>تنبيهات</th><th>التسجيل</th><th></th></tr>
      ${docs.map((d) => { const u = d.data(); return `<tr><td><b>${esc(u.name)}</b>${u.isDemo ? ' <span class="badge warn">Demo</span>' : ''}</td><td dir="ltr">${esc(u.phone)}</td>
      <td>${u.role === 'worker' ? 'صنايعي' : 'عميل'}</td><td>${badge(u.status, USER_STATUS)}</td>
      <td>${u.customerRatingCount ? `${u.customerRatingAvg} ★` : '—'}</td><td>${u.reportsCount || 0}</td>
      <td>${u.flags?.sharedDevice ? '<span class="badge bad">جهاز مشترك</span>' : ''}${u.flags?.manyDevices ? ' <span class="badge warn">أجهزة كثيرة</span>' : ''}</td>
      <td>${fmt(u.createdAt)}</td><td><button class="btn small primary" data-u="${d.id}">إدارة</button></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-u]').forEach((b) => b.onclick = () => manageUser(b.dataset.u, load));
  };
  const load = async () => {
    const phone = $('#uPhone').value.trim().replace(/^\+20/, '0');
    const q = phone ? query(collection(db, 'users'), where('phone', '==', phone)) : query(collection(db, 'users'), where('role', '==', $('#uRole').value), orderBy('createdAt', 'desc'), limit(200));
    render((await getDocs(q)).docs);
  };
  $('#uSearch').onclick = load; $('#uRole').onchange = load;
  $('#uAlerts').onclick = async () => {
    const s = await getDocs(query(collection(db, 'adminAlerts'), where('resolved', '==', false), limit(100)));
    openModal(`<h3>تنبيهات الحسابات المكررة/المشبوهة</h3>${s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>النوع</th><th>الحسابات</th><th>التاريخ</th><th></th></tr>${s.docs.map((d) => { const a = d.data(); return `<tr><td>${a.type === 'shared_device' ? 'نفس الجهاز لعدة حسابات' : 'دخول من أجهزة كثيرة'}</td><td dir="ltr" class="small">${esc((a.uids || [a.uid]).join(', '))}</td><td>${fmt(a.createdAt)}</td><td><button class="btn small" data-res="${d.id}">تم المراجعة</button></td></tr>`; }).join('')}</table>`}`);
    document.querySelectorAll('[data-res]').forEach((b) => b.onclick = () => run(b, async () => { await updateDoc(doc(db, 'adminAlerts', b.dataset.res), { resolved: true }); b.closest('tr').remove(); }));
  };
  await load();
};

async function manageUser(uid, reload) {
  const u = (await getDoc(doc(db, 'users', uid))).data();
  openModal(`<h3>${esc(u.name)} ${badge(u.status, USER_STATUS)}</h3>
    <div class="kv"><div>المعرف</div><div dir="ltr" class="small">${esc(uid)}</div><div>الهاتف</div><div dir="ltr">${esc(u.phone)}</div>
    <div>البريد</div><div>${esc(u.email) || '—'}</div><div>آخر دخول</div><div>${fmt(u.lastLoginAt)}</div><div>سبب الحالة</div><div>${esc(u.statusReason) || '—'}</div>
    <div>ملاحظات الإدارة</div><div>${esc(u.adminNote) || '—'}</div></div><hr>
    <label>الاسم<input id="mName" value="${esc(u.name)}"></label>
    <label>ملاحظة إدارية داخلية<textarea id="mNote">${esc(u.adminNote || '')}</textarea></label>
    <button class="btn primary" id="mSave">حفظ</button><hr>
    <label>السبب (يظهر للمستخدم)<input id="mReason"></label>
    <label>حظر مؤقت حتى (اختياري)<input type="date" id="mUntil"></label>
    <div class="row" style="margin-top:10px">
      <button class="btn success" id="mActive">تفعيل</button><button class="btn warn" id="mSuspend">إيقاف</button>
      <button class="btn danger" id="mBan">حظر</button>
      ${can() ? '<button class="btn ghost" id="mDelete" style="color:#dc2626">حذف الحساب</button>' : ''}
    </div>`);
  const status = (s, btn) => run(btn, async () => {
    const until = $('#mUntil').value ? new Date($('#mUntil').value + 'T23:59:00').getTime() : null;
    await call('adminSetUserStatus', { uid, status: s, reason: $('#mReason').value.trim(), until: s === 'banned' ? until : null });
    closeModal(); reload();
  });
  $('#mSave').onclick = (e) => run(e.target, () => call('adminUpdateUser', { uid, name: $('#mName').value.trim(), adminNote: $('#mNote').value }));
  $('#mActive').onclick = (e) => status('active', e.target);
  $('#mSuspend').onclick = (e) => { if (!$('#mReason').value.trim()) return toast('اكتب السبب', true); status('suspended', e.target); };
  $('#mBan').onclick = (e) => { if (!$('#mReason').value.trim()) return toast('اكتب السبب', true); status('banned', e.target); };
  const del = $('#mDelete');
  if (del) del.onclick = (e) => {
    const reason = prompt('سبب الحذف (إجراء نهائي):'); if (!reason) return;
    run(e.target, async () => { await call('adminDeleteUser', { uid, reason }); closeModal(); reload(); });
  };
}

// ------------------------------------------------------------- 📋 الطلبات
RENDER.requests = async (el) => {
  el.innerHTML = `
    <div class="card row">
      <select id="rStatus"><option value="">كل الحالات</option>${Object.entries(STATUS).map(([k, [t]]) => `<option value="${k}">${t}</option>`).join('')}</select>
      <select id="rEmerg"><option value="">الكل</option><option value="1">طوارئ فقط</option></select>
      <input id="rCode" placeholder="رقم الطلب (6 حروف)" dir="ltr" style="text-transform:uppercase">
      <button class="btn primary" id="rLoad">بحث</button>
    </div>
    <div class="card"><div class="table-wrap" id="rTable"></div></div>`;
  const load = async () => {
    const code = $('#rCode').value.trim().toUpperCase();
    let q;
    if (code) q = query(collection(db, 'requests'), where('code', '==', code));
    else if ($('#rStatus').value) q = query(collection(db, 'requests'), where('status', '==', $('#rStatus').value), orderBy('createdAt', 'desc'), limit(200));
    else if ($('#rEmerg').value) q = query(collection(db, 'requests'), where('isEmergency', '==', true), orderBy('createdAt', 'desc'), limit(200));
    else q = query(collection(db, 'requests'), orderBy('createdAt', 'desc'), limit(200));
    const s = await getDocs(q);
    $('#rTable').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>الرقم</th><th>الخدمة</th><th>العميل</th><th>الصنايعي</th><th>الحالة</th><th>القيمة</th><th>العمولة</th><th>التاريخ</th><th></th></tr>
      ${s.docs.map((d) => { const r = d.data(); return `<tr><td dir="ltr"><b>${esc(r.code)}</b> ${r.isEmergency ? '🚨' : ''}</td><td>${esc(loc(r.serviceName || r.categoryName))}</td>
        <td>${esc(r.customerName)}</td><td>${esc(r.workerName || '—')}</td><td>${badge(r.status)}</td><td>${r.agreedPrice ? money(r.agreedPrice) : '—'}</td>
        <td>${r.commissionAmount ? money(r.commissionAmount) + ' ' + badge(r.commissionStatus, COM_STATUS) : '—'}</td><td>${fmt(r.createdAt)}</td>
        <td><button class="btn small primary" data-r="${d.id}">تفاصيل</button></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-r]').forEach((b) => b.onclick = () => requestDetails(b.dataset.r));
  };
  $('#rLoad').onclick = load;
  await load();
};

async function requestDetails(id) {
  const [rs, hs, ms, rv, rp] = await Promise.all([
    getDoc(doc(db, 'requests', id)),
    getDocs(query(collection(db, `requests/${id}/history`), orderBy('at'))),
    getDocs(query(collection(db, `requests/${id}/messages`), orderBy('createdAt', 'desc'), limit(50))),
    getDocs(query(collection(db, 'reviews'), where('requestId', '==', id))),
    getDocs(query(collection(db, 'reports'), where('requestId', '==', id))),
  ]);
  const r = rs.data();
  const by = { customer: 'العميل', worker: 'الصنايعي', admin: 'الإدارة' };
  openModal(`<h3>طلب ${esc(r.code)} ${badge(r.status)} ${r.isEmergency ? '<span class="badge bad">طوارئ</span>' : ''}</h3>
    <div class="kv">
      <div>الخدمة</div><div>${esc(loc(r.serviceName || r.categoryName))}</div>
      <div>العميل</div><div>${esc(r.customerName)} — <span dir="ltr">${esc(r.customerPhone || '')}</span> <span class="small muted" dir="ltr">${esc(r.customerId)}</span></div>
      <div>الصنايعي</div><div>${esc(r.workerName || '—')} <span dir="ltr">${esc(r.workerPhone || '')}</span></div>
      <div>الوصف</div><div>${esc(r.description) || '—'}</div>
      <div>الموقع</div><div>${esc(r.location?.address)} <a target="_blank" rel="noopener" href="https://www.google.com/maps?q=${r.location?.lat},${r.location?.lng}">خريطة</a></div>
      <div>الموعد</div><div>${fmt(r.scheduledAt)}</div>
      <div>قيمة الخدمة</div><div>${r.agreedPrice ? money(r.agreedPrice) : '—'}</div>
      <div>العمولة</div><div>${r.commissionAmount ? `${money(r.commissionAmount)} (${(r.commissionRate * 100).toFixed(1)}%) ${badge(r.commissionStatus, COM_STATUS)}` : '—'}</div>
      <div>الإلغاء</div><div>${r.cancelReason ? `${esc(r.cancelReason)} — ${esc(r.cancelNote)} (${by[r.cancelledBy] || ''})` : '—'}</div>
      <div>صنايعية تم إشعارهم</div><div>${(r.notifiedWorkerIds || []).length}</div>
    </div>
    ${(r.images || []).length ? `<h4>صور المشكلة</h4><div class="thumbs">${(await Promise.all(r.images.map((u) => imgTag(u)))).join('')}</div>` : ''}
    <h4>سجل الحالات</h4><ul class="timeline">${hs.docs.map((h) => { const x = h.data(); return `<li>${fmt(x.at)} — ${badge(x.to)} بواسطة ${by[x.by] || esc(x.by)} ${x.note ? '— ' + esc(x.note) : ''}</li>`; }).join('')}</ul>
    <h4>التقييمات</h4>${rv.empty ? '<p class="muted">لا يوجد</p>' : rv.docs.map((d) => { const x = d.data(); return `<p>${x.direction === 'c2w' ? 'العميل ← الصنايعي' : 'الصنايعي ← العميل'}: ${'★'.repeat(x.stars)} ${esc(x.comment)}</p>`; }).join('')}
    <h4>البلاغات المرتبطة</h4>${rp.empty ? '<p class="muted">لا يوجد</p>' : rp.docs.map((d) => `<p>${esc(REPORT_TYPES[d.data().type])} — ${badge(d.data().status, REPORT_STATUS)}</p>`).join('')}
    <h4>آخر رسائل الشات</h4><ul class="timeline">${ms.docs.map((m) => { const x = m.data(); return `<li>${x.senderId === r.customerId ? 'العميل' : 'الصنايعي'}: ${x.type === 'text' ? esc(x.text) : x.type === 'image' ? '📷 صورة' : '📍 موقع'} <span class="muted small">${fmt(x.createdAt)}</span></li>`; }).join('') || '<li class="muted">لا يوجد</li>'}</ul>`);
}

// ------------------------------------------------------------- 💳 المالية
RENDER.finance = async (el) => {
  const set = (await getDoc(doc(db, 'settings', 'public'))).data() || {};
  el.innerHTML = `
    <div class="grid kpis" id="fK"></div>
    <div class="card"><h3>إثباتات تحويل بانتظار التأكيد</h3><p class="muted small">⚠️ لا يوجد تحقق تلقائي من InstaPay — طابق رقم العملية والمبلغ مع كشف حسابك قبل التأكيد.</p><div class="table-wrap" id="fPay"></div></div>
    <div class="card"><h3>العمولات</h3><div class="row"><select id="fCs"><option value="due">مستحقة</option><option value="claimed">قيد المراجعة</option><option value="paid">مدفوعة</option></select></div><div class="table-wrap" id="fCom"></div></div>
    <div class="card"><h3>نسبة العمولة</h3><div class="row"><input type="number" id="fRate" step="0.1" min="0" max="30" value="${((set.commissionRate ?? 0.05) * 100).toFixed(1)}"> % <button class="btn primary" id="fRateSave">حفظ</button></div>
    <p class="muted small">التغيير يسري على الطلبات التي يتم تأكيد سعرها بعد الحفظ فقط.</p></div>`;
  const [due, overdue, paid, total] = await Promise.all([
    getAggregateFromServer(query(collection(db, 'commissions'), where('status', 'in', ['due', 'claimed'])), { s: sum('amount') }),
    getDocs(query(collection(db, 'commissions'), where('status', '==', 'due'), where('createdAt', '<=', Timestamp.fromMillis(Date.now() - (set.overdueDays ?? 7) * 86400000)))),
    getAggregateFromServer(query(collection(db, 'commissions'), where('status', '==', 'paid')), { s: sum('amount') }),
    getAggregateFromServer(collection(db, 'commissions'), { s: sum('amount') }),
  ]);
  const overdueSum = overdue.docs.reduce((a, d) => a + Number(d.data().amount || 0), 0);
  const overdueWorkers = new Set(overdue.docs.map((d) => d.data().workerId)).size;
  const kpi = (l, v) => `<div class="kpi"><div class="v">${v}</div><div class="l">${l}</div></div>`;
  $('#fK').innerHTML = kpi('إجمالي العمولات', money(total.data().s)) + kpi('المدفوع', money(paid.data().s)) + kpi('المستحق', money(due.data().s)) + kpi('المتأخر', money(overdueSum)) + kpi('صنايعية عليهم متأخرات', overdueWorkers);

  const loadPay = async () => {
    const s = await getDocs(query(collection(db, 'payments'), where('status', '==', 'pending_review'), orderBy('createdAt', 'desc'), limit(100)));
    $('#fPay').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>الصنايعي</th><th>المبلغ</th><th>رقم العملية</th><th>حساب المحوّل</th><th>عدد العمولات</th><th>التاريخ</th><th>إيصال</th><th></th></tr>
      ${s.docs.map((d) => { const p = d.data(); return `<tr><td>${esc(p.workerName)}<br><span dir="ltr" class="small">${esc(p.workerPhone)}</span></td><td><b>${money(p.amount)}</b></td><td dir="ltr">${esc(p.reference)}</td><td dir="ltr">${esc(p.senderAccount) || '—'}</td><td>${p.commissionIds.length}</td><td>${fmt(p.createdAt)}</td>
      <td>${p.receiptRef ? `<button class="btn small" data-rc="${esc(p.receiptRef)}">عرض</button>` : '—'}</td>
      <td><button class="btn small success" data-pc="${d.id}">تأكيد</button> <button class="btn small danger" data-pr="${d.id}">رفض</button></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-rc]').forEach((b) => b.onclick = async () => { const u = await imgFromPath(b.dataset.rc); openModal(u ? `<img class="id-img" src="${u}">` : 'تعذر التحميل'); });
    el.querySelectorAll('[data-pc]').forEach((b) => b.onclick = () => { if (!confirm('تأكيد استلام التحويل بعد مطابقته؟')) return; run(b, async () => { await call('adminReviewPayment', { paymentId: b.dataset.pc, decision: 'confirm' }); loadPay(); loadCom(); refreshCounters(); }); });
    el.querySelectorAll('[data-pr]').forEach((b) => b.onclick = () => { const note = prompt('سبب الرفض:'); if (!note) return; run(b, async () => { await call('adminReviewPayment', { paymentId: b.dataset.pr, decision: 'reject', note }); loadPay(); loadCom(); refreshCounters(); }); });
  };
  const loadCom = async () => {
    const s = await getDocs(query(collection(db, 'commissions'), where('status', '==', $('#fCs').value), orderBy('createdAt', 'desc'), limit(200)));
    $('#fCom').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>الطلب</th><th>الصنايعي</th><th>قيمة الخدمة</th><th>النسبة</th><th>العمولة</th><th>الحالة</th><th>التاريخ</th></tr>
      ${s.docs.map((d) => { const c = d.data(); return `<tr><td dir="ltr">${esc(c.requestCode)}</td><td>${esc(c.workerName)}</td><td>${money(c.servicePrice)}</td><td>${(c.rate * 100).toFixed(1)}%</td><td><b>${money(c.amount)}</b></td><td>${badge(c.status, COM_STATUS)}</td><td>${fmt(c.createdAt)}</td></tr>`; }).join('')}</table>`;
  };
  $('#fCs').onchange = loadCom;
  $('#fRateSave').onclick = (e) => run(e.target, () => call('adminUpdateSettings', { commissionRate: Number($('#fRate').value) / 100 }));
  await Promise.all([loadPay(), loadCom()]);
};

// ------------------------------------------------------------- 🧰 المهن والخدمات
RENDER.catalog = async (el) => {
  catalogCache = null;
  const cat = await catalog();
  el.innerHTML = `
    <div class="card"><h3>إضافة / تعديل مهنة</h3>
      <div class="grid two">
        <label>المعرف (إنجليزي بدون مسافات)<input id="cId" placeholder="plumber" dir="ltr"></label>
        <label>الاسم بالعربي<input id="cAr"></label><label>الاسم بالإنجليزي<input id="cEn" dir="ltr"></label>
        <label>أيقونة Material (مثل plumbing)<input id="cIcon" dir="ltr" value="handyman"></label>
        <label>أو رفع صورة أيقونة<input type="file" id="cIconFile" accept="image/*"></label>
        <label>الترتيب<input type="number" id="cOrder" value="${cat.cats.length}"></label>
      </div>
      <div class="row" style="margin-top:10px"><label style="display:inline"><input type="checkbox" id="cActive" checked style="width:auto"> مفعلة</label><button class="btn primary" id="cSave">حفظ المهنة</button></div>
    </div>
    <div class="card"><h3>المهن والخدمات</h3><p class="muted small">أي تعديل هنا يظهر في التطبيق فورًا بدون تحديث. التعطيل أفضل من الحذف للحفاظ على سجل الطلبات القديمة.</p>
      ${cat.cats.map((c) => `<details style="margin-bottom:8px"><summary><b>${esc(c.nameAr)}</b> / ${esc(c.nameEn)} ${c.active === false ? '<span class="badge bad">معطلة</span>' : '<span class="badge ok">مفعلة</span>'}
        <button class="btn small" data-ec="${c.id}">تعديل</button> <button class="btn small" data-tc="${c.id}">${c.active === false ? 'تفعيل' : 'تعطيل'}</button></summary>
        <table><tr><th>الخدمة (عربي)</th><th>English</th><th>الحالة</th><th></th></tr>
        ${cat.svcs.filter((s) => s.categoryId === c.id).map((s) => `<tr><td>${esc(s.nameAr)}</td><td>${esc(s.nameEn)}</td><td>${s.active === false ? '<span class="badge bad">معطلة</span>' : '<span class="badge ok">مفعلة</span>'}</td>
          <td><button class="btn small" data-es="${s.id}">تعديل</button> <button class="btn small" data-ts="${s.id}">${s.active === false ? 'تفعيل' : 'تعطيل'}</button></td></tr>`).join('')}
        <tr><td><input placeholder="خدمة جديدة بالعربي" id="nsAr-${c.id}"></td><td><input placeholder="English" dir="ltr" id="nsEn-${c.id}"></td><td></td><td><button class="btn small primary" data-ns="${c.id}">إضافة</button></td></tr></table></details>`).join('')}
    </div>`;
  const log = (action, id, details) => addDoc(collection(db, 'adminActions'), { adminId: me.uid, adminEmail: me.email, action, targetType: 'catalog', targetId: id, details, createdAt: serverTimestamp() });
  $('#cSave').onclick = (e) => run(e.target, async () => {
    const id = $('#cId').value.trim().toLowerCase().replace(/[^a-z0-9_]/g, '_');
    if (!id || !$('#cAr').value.trim() || !$('#cEn').value.trim()) throw new Error('أكمل البيانات');
    let iconUrl;
    const f = $('#cIconFile').files[0];
    if (f) {
      // الخطة المجانية: الأيقونة بتتخزن كـ data URL (لازم تكون صغيرة)
      if (f.size > 100 * 1024) throw new Error('الأيقونة لازم تكون أقل من 100KB');
      iconUrl = await new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(fr.result); fr.onerror = rej; fr.readAsDataURL(f); });
    }
    const data = { nameAr: $('#cAr').value.trim(), nameEn: $('#cEn').value.trim(), icon: $('#cIcon').value.trim() || 'handyman', active: $('#cActive').checked, order: Number($('#cOrder').value) || 0, updatedAt: serverTimestamp() };
    if (iconUrl) data.iconUrl = iconUrl;
    await setDoc(doc(db, 'categories', id), data, { merge: true });
    await log('category_save', id, { nameAr: data.nameAr });
    RENDER.catalog(el);
  });
  el.querySelectorAll('[data-ec]').forEach((b) => b.onclick = (ev) => {
    ev.preventDefault(); const c = cat.cats.find((x) => x.id === b.dataset.ec);
    $('#cId').value = c.id; $('#cAr').value = c.nameAr; $('#cEn').value = c.nameEn; $('#cIcon').value = c.icon || ''; $('#cOrder').value = c.order || 0; $('#cActive').checked = c.active !== false;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });
  el.querySelectorAll('[data-tc]').forEach((b) => b.onclick = (ev) => { ev.preventDefault(); const c = cat.cats.find((x) => x.id === b.dataset.tc);
    run(b, async () => { await updateDoc(doc(db, 'categories', c.id), { active: c.active === false }); await log('category_toggle', c.id, { active: c.active === false }); RENDER.catalog(el); }); });
  el.querySelectorAll('[data-ts]').forEach((b) => b.onclick = () => { const s = cat.svcs.find((x) => x.id === b.dataset.ts);
    run(b, async () => { await updateDoc(doc(db, 'services', s.id), { active: s.active === false }); await log('service_toggle', s.id, { active: s.active === false }); RENDER.catalog(el); }); });
  el.querySelectorAll('[data-es]').forEach((b) => b.onclick = () => { const s = cat.svcs.find((x) => x.id === b.dataset.es);
    const ar = prompt('الاسم بالعربي', s.nameAr); if (ar === null) return; const en = prompt('English name', s.nameEn); if (en === null) return;
    run(b, async () => { await updateDoc(doc(db, 'services', s.id), { nameAr: ar.trim(), nameEn: en.trim() }); await log('service_edit', s.id, { nameAr: ar }); RENDER.catalog(el); }); });
  el.querySelectorAll('[data-ns]').forEach((b) => b.onclick = () => { const cid = b.dataset.ns; const ar = $(`#nsAr-${cid}`).value.trim(); const en = $(`#nsEn-${cid}`).value.trim();
    if (!ar || !en) return toast('اكتب الاسم بالعربي والإنجليزي', true);
    run(b, async () => { const order = cat.svcs.filter((s) => s.categoryId === cid).length; const r = await addDoc(collection(db, 'services'), { categoryId: cid, nameAr: ar, nameEn: en, active: true, order, updatedAt: serverTimestamp() }); await log('service_add', r.id, { nameAr: ar }); RENDER.catalog(el); }); });
};

// ------------------------------------------------------------- 📍 المناطق
RENDER.locations = async (el) => {
  catalogCache = null;
  const cat = await catalog();
  const govs = cat.locs.filter((l) => l.type === 'governorate').sort((a, b) => (a.order || 0) - (b.order || 0));
  el.innerHTML = `<div class="card"><h3>إضافة مركز/مدينة أو منطقة/قرية</h3>
    <p class="muted small">الإحداثيات (اختيارية) تُستخدم كمركز للبحث عند اختيار العميل للمكان يدويًا. احصل عليها من خرائط Google (اضغط مطولًا على المكان).</p>
    <div class="grid two">
      <label>النوع<select id="lType"><option value="city">مركز / مدينة</option><option value="area">منطقة / قرية</option></select></label>
      <label>تابع لـ<select id="lParent">${govs.map((g) => `<option value="${g.id}">${esc(g.nameAr)}</option>`).join('')}${cat.locs.filter((l) => l.type === 'city').map((c) => `<option value="${c.id}">↳ ${esc(c.nameAr)} (${esc(cat.locs.find((g) => g.id === c.parentId)?.nameAr || '')})</option>`).join('')}</select></label>
      <label>الاسم بالعربي<input id="lAr"></label><label>English<input id="lEn" dir="ltr"></label>
      <label>خط العرض (lat)<input id="lLat" dir="ltr" placeholder="30.0444"></label><label>خط الطول (lng)<input id="lLng" dir="ltr" placeholder="31.2357"></label>
    </div><button class="btn primary" id="lSave" style="margin-top:10px">إضافة</button></div>
    <div class="card"><h3>المحافظات والمناطق</h3>${govs.map((g) => `<details><summary><b>${esc(g.nameAr)}</b> ${g.lat ? '' : '<span class="badge warn">بدون إحداثيات</span>'}</summary><ul>${cat.locs.filter((c) => c.parentId === g.id).map((c) => `<li>${esc(c.nameAr)} <button class="btn small" data-ld="${c.id}">${c.active === false ? 'تفعيل' : 'تعطيل'}</button><ul>${cat.locs.filter((a) => a.parentId === c.id).map((a) => `<li>${esc(a.nameAr)} <button class="btn small" data-ld="${a.id}">${a.active === false ? 'تفعيل' : 'تعطيل'}</button></li>`).join('')}</ul></li>`).join('') || '<li class="muted">لا يوجد</li>'}</ul></details>`).join('')}</div>`;
  $('#lSave').onclick = (e) => run(e.target, async () => {
    const ar = $('#lAr').value.trim(); if (!ar) throw new Error('اكتب الاسم');
    const lat = parseFloat($('#lLat').value); const lng = parseFloat($('#lLng').value);
    const data = { type: $('#lType').value, parentId: $('#lParent').value, nameAr: ar, nameEn: $('#lEn').value.trim(), active: true, code: '', updatedAt: serverTimestamp() };
    if (!isNaN(lat) && !isNaN(lng)) { data.lat = lat; data.lng = lng; }
    await addDoc(collection(db, 'locations'), data);
    RENDER.locations(el);
  });
  el.querySelectorAll('[data-ld]').forEach((b) => b.onclick = () => { const l = cat.locs.find((x) => x.id === b.dataset.ld); run(b, async () => { await updateDoc(doc(db, 'locations', l.id), { active: l.active === false }); RENDER.locations(el); }); });
};

// ------------------------------------------------------------- 🚩 البلاغات
RENDER.reports = async (el) => {
  el.innerHTML = `<div class="card row"><select id="pStatus">${Object.entries(REPORT_STATUS).map(([k, [t]]) => `<option value="${k}">${t}</option>`).join('')}</select></div><div class="card"><div class="table-wrap" id="pTable"></div></div>`;
  const load = async () => {
    const s = await getDocs(query(collection(db, 'reports'), where('status', '==', $('#pStatus').value), orderBy('createdAt', 'desc'), limit(200)));
    $('#pTable').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>النوع</th><th>المُبلِّغ</th><th>ضد</th><th>الطلب</th><th>الوصف</th><th>التاريخ</th><th></th></tr>
      ${s.docs.map((d) => { const p = d.data(); return `<tr><td>${esc(REPORT_TYPES[p.type] || p.type)}</td><td>${esc(p.reporterName)} (${p.reporterRole === 'worker' ? 'صنايعي' : 'عميل'})</td>
      <td dir="ltr" class="small">${esc(p.againstId || '—')}</td><td dir="ltr">${esc(p.requestCode || '—')}</td><td>${esc(p.description).slice(0, 120)}</td><td>${fmt(p.createdAt)}</td>
      <td><button class="btn small primary" data-p="${d.id}">معالجة</button></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-p]').forEach((b) => b.onclick = () => handleReport(b.dataset.p, load));
  };
  $('#pStatus').onchange = load;
  await load();
};
async function handleReport(id, reload) {
  const p = (await getDoc(doc(db, 'reports', id))).data();
  const imgs = await Promise.all((p.images || []).map(imgFromPath));
  openModal(`<h3>${esc(REPORT_TYPES[p.type] || p.type)} ${badge(p.status, REPORT_STATUS)}</h3>
    <div class="kv"><div>المُبلِّغ</div><div>${esc(p.reporterName)} <span class="small" dir="ltr">${esc(p.reporterId)}</span></div>
    <div>ضد</div><div dir="ltr" class="small">${esc(p.againstId || '—')}</div><div>الطلب</div><div>${p.requestId ? `<button class="btn small" id="pReq">${esc(p.requestCode)}</button>` : '—'}</div>
    <div>الوصف</div><div>${esc(p.description)}</div></div>
    ${imgs.filter(Boolean).length ? `<div class="thumbs">${imgs.filter(Boolean).map((u) => `<img src="${u}">`).join('')}</div>` : ''}<hr>
    <label>التصنيف<input id="pCat" value="${esc(p.category || '')}" placeholder="مثال: سلوك / جودة / مالي"></label>
    <label>الحالة<select id="pSt">${Object.entries(REPORT_STATUS).map(([k, [t]]) => `<option value="${k}" ${k === p.status ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
    <label>الإجراء المتخذ<input id="pAct" value="${esc(p.actionTaken || '')}" placeholder="إنذار / إيقاف مؤقت / حظر / لا شيء"></label>
    <label>ملاحظة داخلية<textarea id="pNote">${esc(p.adminNote || '')}</textarea></label>
    <div class="row" style="margin-top:10px"><button class="btn primary" id="pSave">حفظ</button>${p.againstId ? '<button class="btn warn" id="pUser">إدارة الحساب المُبلَّغ عنه</button>' : ''}</div>`);
  $('#pSave').onclick = (e) => run(e.target, async () => {
    await call('adminUpdateReport', { reportId: id, status: $('#pSt').value, adminNote: $('#pNote').value, actionTaken: $('#pAct').value, category: $('#pCat').value.trim() || undefined });
    closeModal(); reload(); refreshCounters();
  });
  if ($('#pUser')) $('#pUser').onclick = () => manageUser(p.againstId, reload);
  if ($('#pReq')) $('#pReq').onclick = () => requestDetails(p.requestId);
}

// ------------------------------------------------------------- ⭐ التقييمات
RENDER.reviews = async (el) => {
  el.innerHTML = `<div class="card row"><select id="vDir"><option value="c2w">تقييمات الصنايعية (عامة)</option><option value="w2c">تقييمات العملاء (داخلية)</option></select></div><div class="card"><div class="table-wrap" id="vTable"></div></div>`;
  const load = async () => {
    const s = await getDocs(query(collection(db, 'reviews'), where('direction', '==', $('#vDir').value), orderBy('createdAt', 'desc'), limit(200)));
    $('#vTable').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>من</th><th>إلى</th><th>النجوم</th><th>التعليق</th><th>التاريخ</th><th>الحالة</th><th></th></tr>
      ${s.docs.map((d) => { const r = d.data(); return `<tr><td>${esc(r.fromName)}</td><td dir="ltr" class="small">${esc(r.toId)}</td><td>${'★'.repeat(r.stars)}</td><td>${esc(r.comment)}</td><td>${fmt(r.createdAt)}</td>
      <td>${r.hidden ? '<span class="badge bad">مخفي</span>' : '<span class="badge ok">ظاهر</span>'}</td><td><button class="btn small" data-v="${d.id}" data-h="${r.hidden ? 0 : 1}">${r.hidden ? 'إظهار' : 'إخفاء (مخالف)'}</button></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-v]').forEach((b) => b.onclick = () => run(b, async () => { await call('adminSetReviewHidden', { reviewId: b.dataset.v, hidden: b.dataset.h === '1', note: '' }); load(); }));
  };
  $('#vDir').onchange = load;
  await load();
};

// ------------------------------------------------------------- 📣 الإشعارات
RENDER.notify = async (el) => {
  const cat = await catalog();
  el.innerHTML = `<div class="card"><h3>إرسال إشعار Push مستهدف</h3>
    <div class="grid two">
      <label>الجمهور<select id="nT"><option value="all">جميع المستخدمين</option><option value="customers">جميع العملاء</option><option value="workers">جميع الصنايعية</option><option value="category">صنايعية مهنة معينة</option><option value="governorate">محافظة معينة</option><option value="user">مستخدم محدد</option></select></label>
      <label id="nVWrap" class="hidden">القيمة<select id="nVCat">${cat.cats.map((c) => `<option value="${c.id}">${esc(c.nameAr)}</option>`).join('')}</select>
        <select id="nVGov" class="hidden">${cat.locs.filter((l) => l.type === 'governorate').map((g) => `<option value="${esc(g.code)}">${esc(g.nameAr)}</option>`).join('')}</select>
        <input id="nVUser" class="hidden" placeholder="رقم الموبايل أو معرف المستخدم" dir="ltr"></label>
      <label>العنوان (عربي)<input id="nTa" maxlength="80"></label><label>Title (English)<input id="nTe" dir="ltr" maxlength="80"></label>
      <label>النص (عربي)<textarea id="nBa" maxlength="400"></textarea></label><label>Body (English)<textarea id="nBe" dir="ltr" maxlength="400"></textarea></label>
    </div><p class="muted small">لو تركت الإنجليزي فارغًا سيُرسل النص العربي لمستخدمي اللغة الإنجليزية.</p>
    <button class="btn primary" id="nSend">إرسال</button></div>
    <div class="card"><h3>آخر الإشعارات المرسلة</h3><div id="nHist"></div></div>`;
  const sync = () => { const t = $('#nT').value; $('#nVWrap').classList.toggle('hidden', !['category', 'governorate', 'user'].includes(t));
    $('#nVCat').classList.toggle('hidden', t !== 'category'); $('#nVGov').classList.toggle('hidden', t !== 'governorate'); $('#nVUser').classList.toggle('hidden', t !== 'user'); };
  $('#nT').onchange = sync;
  const hist = async () => { const s = await getDocs(query(collection(db, 'broadcasts'), orderBy('createdAt', 'desc'), limit(20)));
    $('#nHist').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>التاريخ</th><th>الجمهور</th><th>العنوان</th></tr>${s.docs.map((d) => { const b = d.data(); return `<tr><td>${fmt(b.createdAt)}</td><td>${esc(b.target)} ${esc(b.value)}</td><td>${esc(b.titleAr)}</td></tr>`; }).join('')}</table>`; };
  $('#nSend').onclick = (e) => {
    const t = $('#nT').value;
    const value = t === 'category' ? $('#nVCat').value : t === 'governorate' ? $('#nVGov').value : t === 'user' ? $('#nVUser').value.trim() : '';
    if (!confirm('تأكيد الإرسال؟')) return;
    run(e.target, async () => {
      await call('adminBroadcast', { target: t, value, titleAr: $('#nTa').value.trim(), bodyAr: $('#nBa').value.trim(), titleEn: $('#nTe').value.trim() || undefined, bodyEn: $('#nBe').value.trim() || undefined });
      hist();
    }, 'تم الإرسال ✅');
  };
  await hist();
};

// ------------------------------------------------------------- 💬 الدعم
RENDER.support = async (el) => {
  el.innerHTML = `<div class="card row"><select id="sSt"><option value="open">مفتوحة</option><option value="closed">مغلقة</option></select></div><div class="card"><div class="table-wrap" id="sT"></div></div>`;
  const kinds = { support: 'دعم', technical: 'مشكلة تقنية', complaint: 'شكوى', suggestion: 'اقتراح' };
  const load = async () => {
    const s = await getDocs(query(collection(db, 'supportTickets'), where('status', '==', $('#sSt').value), orderBy('createdAt', 'desc'), limit(200)));
    $('#sT').innerHTML = s.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>النوع</th><th>المستخدم</th><th>الموضوع</th><th>الرسالة</th><th>التاريخ</th><th></th></tr>
      ${s.docs.map((d) => { const t = d.data(); return `<tr><td>${kinds[t.kind] || esc(t.kind)}</td><td>${esc(t.name)}<br><span dir="ltr" class="small">${esc(t.phone)}</span></td><td>${esc(t.subject)}</td><td>${esc(t.message)}${t.reply ? `<br><span class="muted">الرد: ${esc(t.reply)}</span>` : ''}</td><td>${fmt(t.createdAt)}</td>
      <td>${t.status === 'open' ? `<button class="btn small primary" data-s="${d.id}">رد وإغلاق</button>` : ''} <a class="btn small" target="_blank" rel="noopener" href="https://wa.me/2${esc(t.phone)}">واتساب</a></td></tr>`; }).join('')}</table>`;
    el.querySelectorAll('[data-s]').forEach((b) => b.onclick = () => { const reply = prompt('الرد (داخلي — تواصل مع المستخدم هاتفيًا/واتساب):'); if (reply === null) return;
      run(b, async () => { await updateDoc(doc(db, 'supportTickets', b.dataset.s), { status: 'closed', reply, closedBy: me.uid, closedAt: serverTimestamp() }); load(); refreshCounters(); }); });
  };
  $('#sSt').onchange = load;
  await load();
};

// ------------------------------------------------------------- ⚙️ الإعدادات
RENDER.settings = async (el) => {
  const s = (await getDoc(doc(db, 'settings', 'public'))).data() || {};
  const pub = (await getDoc(doc(db, 'settings', 'public'))).data() || {};
  const br = s.badgeRules || {};
  el.innerHTML = `
    <div class="card"><h3>العمولة والدفع (InstaPay)</h3><div class="grid two">
      <label>نسبة العمولة %<input type="number" id="sRate" step="0.1" value="${((s.commissionRate ?? 0.05) * 100).toFixed(1)}"></label>
      <label>تعتبر العمولة متأخرة بعد (يوم)<input type="number" id="sOver" value="${s.overdueDays ?? 7}"></label>
      <label>عنوان InstaPay (IPA) مثل name@instapay<input id="sIpa" dir="ltr" value="${esc(s.instapayHandle || '')}"></label>
      <label>رقم الموبايل المرتبط بـ InstaPay<input id="sIpp" dir="ltr" value="${esc(s.instapayPhone || '')}"></label>
    </div><button class="btn primary" id="sPay" style="margin-top:10px">حفظ</button></div>
    ${can() ? `
    <div class="card"><h3>الطوارئ والطلبات المفتوحة</h3><div class="grid two">
      <label>نطاق إشعار الطوارئ (كم)<input type="number" id="sEm" value="${s.emergencyRadiusKm ?? 15}"></label>
      <label>نطاق الطلبات المفتوحة (كم)<input type="number" id="sOp" value="${s.openRequestRadiusKm ?? 25}"></label>
      <label>أقصى عدد صنايعية يتم إشعارهم<input type="number" id="sMax" value="${s.maxNotifiedWorkers ?? 30}"></label>
    </div><button class="btn primary" id="sRad" style="margin-top:10px">حفظ</button></div>
    <div class="card"><h3>قواعد الشارات التلقائية</h3><div class="grid two">
      <label>⭐ الأعلى تقييمًا: أقل متوسط<input type="number" step="0.1" id="bTrA" value="${br.topRatedMinAvg ?? 4.7}"></label>
      <label>⭐ أقل عدد تقييمات<input type="number" id="bTrC" value="${br.topRatedMinCount ?? 10}"></label>
      <label>🏆 الأكثر إنجازًا: عدد الخدمات المكتملة<input type="number" id="bMc" value="${br.mostCompletedMin ?? 50}"></label>
    </div><button class="btn primary" id="sBadge" style="margin-top:10px">حفظ</button><p class="muted small">الشارات بتتحسب تلقائيًا في التطبيق من التقييمات وعدد الخدمات المكتملة. (✓ موثّق = البطاقة اتراجعت)</p></div>
    <div class="card"><h3>بيانات الدعم ورابط التطبيق (تظهر في التطبيق)</h3><div class="grid two">
      <label>رقم الدعم<input id="pPh" dir="ltr" value="${esc(pub.supportPhone || '')}"></label>
      <label>واتساب الدعم<input id="pWa" dir="ltr" value="${esc(pub.supportWhatsapp || '')}"></label>
      <label>بريد الدعم<input id="pEm" dir="ltr" value="${esc(pub.supportEmail || '')}"></label>
      <label>رابط Google Play<input id="pPlay" dir="ltr" value="${esc(pub.playStoreUrl || '')}"></label>
    </div><button class="btn primary" id="sPub" style="margin-top:10px">حفظ</button></div>` : ''}`;
  $('#sPay').onclick = (e) => run(e.target, () => call('adminUpdateSettings', { commissionRate: Number($('#sRate').value) / 100, overdueDays: Number($('#sOver').value), instapayHandle: $('#sIpa').value.trim(), instapayPhone: $('#sIpp').value.trim() }));
  if (!can()) return;
  $('#sRad').onclick = (e) => run(e.target, () => call('adminUpdateSettings', { emergencyRadiusKm: Number($('#sEm').value), openRequestRadiusKm: Number($('#sOp').value), maxNotifiedWorkers: Number($('#sMax').value) }));
  $('#sBadge').onclick = (e) => run(e.target, () => call('adminUpdateSettings', { badgeRules: {
    topRatedMinAvg: Number($('#bTrA').value), topRatedMinCount: Number($('#bTrC').value), mostCompletedMin: Number($('#bMc').value),
  } }));
  $('#sPub').onclick = (e) => run(e.target, () => setDoc(doc(db, 'settings', 'public'), { supportPhone: $('#pPh').value.trim(), supportWhatsapp: $('#pWa').value.trim(), supportEmail: $('#pEm').value.trim(), playStoreUrl: $('#pPlay').value.trim() }, { merge: true }));
};

// ------------------------------------------------------------- 🛡️ الإدارة والسجل
RENDER.admins = async (el) => {
  const [admins, reqs, log] = await Promise.all([
    getDocs(collection(db, 'admins')),
    getDocs(collection(db, 'adminRequests')),
    getDocs(query(collection(db, 'adminActions'), orderBy('createdAt', 'desc'), limit(150))),
  ]);
  const roles = { super: 'مدير عام', moderator: 'مشرف', finance: 'مالية' };
  const sel = (id, cur) => `<select data-role="${id}">${Object.entries({ ...roles, none: 'إزالة الصلاحية' }).map(([k, v]) => `<option value="${k}" ${k === cur ? 'selected' : ''}>${v}</option>`).join('')}</select>`;
  el.innerHTML = `<div class="card"><h3>طلبات صلاحية جديدة</h3>
    <p class="muted small">أي حد عايز يبقى مشرف: يدخل لوحة التحكم مرة بحسابه (بريد أو Google)، فيظهر هنا وتحدد دوره.</p>
    ${reqs.empty ? '<div class="empty">لا يوجد</div>' : `<table><tr><th>البريد</th><th>التاريخ</th><th>الدور</th><th></th></tr>${reqs.docs.map((d) => `<tr><td dir="ltr">${esc(d.data().email)}</td><td>${fmt(d.data().createdAt)}</td><td>${sel(d.id, 'moderator')}</td><td><button class="btn small primary" data-grant="${d.id}" data-email="${esc(d.data().email)}">منح</button> <button class="btn small" data-deny="${d.id}">تجاهل</button></td></tr>`).join('')}</table>`}</div>
    <div class="card"><h3>المديرون الحاليون</h3>
    <table><tr><th>البريد</th><th>الدور</th><th></th></tr>${admins.docs.map((d) => { const a = d.data(); return `<tr><td dir="ltr">${esc(a.email)} ${a.owner ? '<span class="badge ok">صاحب التطبيق</span>' : ''}${a.demo ? ' <span class="badge warn">تجريبي</span>' : ''}</td><td>${a.owner ? roles.super : sel(d.id, a.role)}</td><td>${a.owner ? '' : `<button class="btn small" data-save="${d.id}" data-email="${esc(a.email)}">حفظ</button>`}</td></tr>`; }).join('')}</table></div>
    <div class="card"><h3>سجل عمليات الإدارة</h3><div class="table-wrap"><table><tr><th>التاريخ</th><th>المدير</th><th>العملية</th><th>الهدف</th><th>تفاصيل</th></tr>
    ${log.docs.map((d) => { const a = d.data(); return `<tr><td>${fmt(a.createdAt)}</td><td dir="ltr" class="small">${esc(a.adminEmail)}</td><td>${esc(a.action)}</td><td dir="ltr" class="small">${esc(a.targetType)}/${esc(a.targetId)}</td><td class="small" dir="ltr">${esc(JSON.stringify(a.details || {})).slice(0, 160)}</td></tr>`; }).join('')}</table></div></div>`;
  const roleOf = (id) => el.querySelector(`[data-role="${id}"]`).value;
  el.querySelectorAll('[data-grant]').forEach((b) => b.onclick = () => run(b, async () => { await call('adminSetAdminRole', { uid: b.dataset.grant, email: b.dataset.email, role: roleOf(b.dataset.grant) }); RENDER.admins(el); }));
  el.querySelectorAll('[data-save]').forEach((b) => b.onclick = () => run(b, async () => { await call('adminSetAdminRole', { uid: b.dataset.save, email: b.dataset.email, role: roleOf(b.dataset.save) }); RENDER.admins(el); }));
  el.querySelectorAll('[data-deny]').forEach((b) => b.onclick = () => run(b, async () => { await deleteDoc(doc(db, 'adminRequests', b.dataset.deny)); RENDER.admins(el); }));
};

// للاستخدام من console أثناء التطوير فقط
export { Timestamp };
