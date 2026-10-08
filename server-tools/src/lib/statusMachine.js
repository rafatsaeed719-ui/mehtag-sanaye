'use strict';
/**
 * نظام حالات الطلب (State Machine)
 *
 *  new ──accept──► accepted ──on_the_way──► on_the_way ──start──► started ──complete──► completed
 *   │  └─propose_time─► proposed ──accept_proposal──► confirmed ─┘                         │
 *   └─reject──► rejected                                                          set_price ▼
 *                                         price_set ──confirm_price──► price_agreed ──(admin)──► commission_paid
 *                                             └──dispute_price──► completed
 *  cancel متاح من أي حالة قبل "completed" مع سبب إلزامي.
 *  التقييم يُسجّل كعلامات customerReviewed / workerReviewed (حالة "تم التقييم").
 */

const S = Object.freeze({
  NEW: 'new',
  ACCEPTED: 'accepted',
  REJECTED: 'rejected',
  PROPOSED: 'proposed',
  CONFIRMED: 'confirmed',
  ON_THE_WAY: 'on_the_way',
  STARTED: 'started',
  COMPLETED: 'completed',
  PRICE_SET: 'price_set',
  PRICE_AGREED: 'price_agreed',
  COMMISSION_PAID: 'commission_paid',
  CANCELLED: 'cancelled',
});

const ALL_STATUSES = Object.values(S);
const CANCELLABLE = [S.NEW, S.ACCEPTED, S.PROPOSED, S.CONFIRMED, S.ON_THE_WAY, S.STARTED];
const ACTIVE = [S.NEW, S.ACCEPTED, S.PROPOSED, S.CONFIRMED, S.ON_THE_WAY, S.STARTED, S.COMPLETED, S.PRICE_SET];
const REVIEWABLE = [S.COMPLETED, S.PRICE_SET, S.PRICE_AGREED, S.COMMISSION_PAID];

const CANCEL_REASONS = Object.freeze({
  customer: ['found_other', 'no_longer_needed', 'worker_late', 'price_disagreement', 'wrong_request', 'proposal_declined', 'other'],
  worker: ['not_available', 'too_far', 'not_my_service', 'customer_unreachable', 'price_disagreement', 'other'],
});

/** action → { by: 'worker'|'customer'|'either', from: [...], to } */
const ACTIONS = Object.freeze({
  accept: { by: 'worker', from: [S.NEW], to: S.ACCEPTED },
  reject: { by: 'worker', from: [S.NEW], to: S.REJECTED },
  propose_time: { by: 'worker', from: [S.NEW, S.ACCEPTED, S.CONFIRMED], to: S.PROPOSED },
  accept_proposal: { by: 'customer', from: [S.PROPOSED], to: S.CONFIRMED },
  on_the_way: { by: 'worker', from: [S.ACCEPTED, S.CONFIRMED], to: S.ON_THE_WAY },
  start: { by: 'worker', from: [S.ACCEPTED, S.CONFIRMED, S.ON_THE_WAY], to: S.STARTED },
  complete: { by: 'worker', from: [S.STARTED], to: S.COMPLETED },
  set_price: { by: 'worker', from: [S.COMPLETED, S.PRICE_SET], to: S.PRICE_SET },
  confirm_price: { by: 'customer', from: [S.PRICE_SET], to: S.PRICE_AGREED },
  dispute_price: { by: 'customer', from: [S.PRICE_SET], to: S.COMPLETED },
  cancel: { by: 'either', from: CANCELLABLE, to: S.CANCELLED },
});

class TransitionError extends Error {
  constructor(code, detail) { super(code); this.code = code; this.detail = detail; }
}

/**
 * يحدد دور المستخدم في الطلب.
 * الطلب المفتوح (بدون صنايعي) يستطيع أي صنايعي موثق ومناسب قبوله فقط.
 */
function actorRole(request, uid, { isEligibleWorker = false } = {}) {
  if (request.customerId === uid) return 'customer';
  if (request.workerId && request.workerId === uid) return 'worker';
  if (!request.workerId && request.open === true && isEligibleWorker) return 'open_worker';
  return null;
}

/**
 * يتحقق من الانتقال ويعيد الحالة الجديدة والتعديلات (بدون أي I/O).
 * @param {object} request الطلب الحالي
 * @param {string} action
 * @param {'customer'|'worker'|'open_worker'} role
 * @param {object} payload
 * @param {number} nowMs
 */
function transition(request, action, role, payload = {}, nowMs = Date.now()) {
  const spec = ACTIONS[action];
  if (!spec) throw new TransitionError('unknown-action', action);
  if (!role) throw new TransitionError('not-participant');

  // الطلب المفتوح: الإجراء الوحيد المسموح لغير الطرف هو "قبول"
  if (role === 'open_worker' && action !== 'accept') throw new TransitionError('not-participant');
  const effectiveRole = role === 'open_worker' ? 'worker' : role;

  if (spec.by !== 'either' && spec.by !== effectiveRole) throw new TransitionError('wrong-role', spec.by);
  if (!spec.from.includes(request.status)) {
    throw new TransitionError('invalid-transition', `${request.status} -> ${action}`);
  }
  // reject مسموح فقط للطلب الموجه لصنايعي بعينه (المفتوح يتجاهله الصنايعي ببساطة)
  if (action === 'reject' && request.open === true && !request.workerId) {
    throw new TransitionError('invalid-transition', 'open request cannot be rejected');
  }

  const patch = { status: spec.to };
  const meta = {};

  switch (action) {
    case 'propose_time': {
      const t = Number(payload.proposedAt);
      if (!Number.isFinite(t) || t < nowMs - 5 * 60 * 1000 || t > nowMs + 90 * 24 * 3600 * 1000) {
        throw new TransitionError('invalid-time');
      }
      patch.proposedAt = t;
      break;
    }
    case 'accept_proposal': {
      patch.scheduledAt = request.proposedAt;
      patch.proposedAt = null;
      break;
    }
    case 'accept': {
      if (role === 'open_worker') meta.claimOpen = true;
      break;
    }
    case 'set_price': {
      const price = Number(payload.price);
      if (!Number.isFinite(price) || price <= 0 || price > 1000000) throw new TransitionError('invalid-price');
      patch.agreedPrice = Math.round(price * 100) / 100;
      break;
    }
    case 'confirm_price': {
      if (!(request.agreedPrice > 0)) throw new TransitionError('invalid-price');
      meta.createCommission = true;
      break;
    }
    case 'dispute_price': {
      patch.agreedPrice = null;
      meta.disputed = true;
      break;
    }
    case 'cancel': {
      const reasons = CANCEL_REASONS[effectiveRole];
      if (!reasons.includes(payload.reason)) throw new TransitionError('invalid-reason');
      const note = typeof payload.note === 'string' ? payload.note.trim().slice(0, 300) : '';
      if (payload.reason === 'other' && note.length < 3) throw new TransitionError('reason-note-required');
      patch.cancelReason = payload.reason;
      patch.cancelNote = note;
      patch.cancelledBy = effectiveRole;
      break;
    }
    default:
      break;
  }
  return { from: request.status, to: spec.to, patch, meta, role: effectiveRole };
}

/** إلى من يذهب إشعار التغيير */
function counterpart(role) { return role === 'customer' ? 'worker' : 'customer'; }

module.exports = {
  S, ALL_STATUSES, ACTIONS, CANCELLABLE, ACTIVE, REVIEWABLE, CANCEL_REASONS,
  TransitionError, transition, actorRole, counterpart,
};
