'use strict';
/**
 * الشارات التلقائية — القواعد قابلة للتعديل من لوحة التحكم (settings/app.badgeRules)
 */

const DEFAULT_BADGE_RULES = Object.freeze({
  topRated: { enabled: true, minAvg: 4.7, minCount: 10 },
  mostCompleted: { enabled: true, minCompleted: 50 },
  fastResponse: { enabled: true, maxAvgMinutes: 15, minResponses: 5, minResponseRate: 0.8 },
});

function mergeRules(rules) {
  const r = rules || {};
  return {
    topRated: { ...DEFAULT_BADGE_RULES.topRated, ...(r.topRated || {}) },
    mostCompleted: { ...DEFAULT_BADGE_RULES.mostCompleted, ...(r.mostCompleted || {}) },
    fastResponse: { ...DEFAULT_BADGE_RULES.fastResponse, ...(r.fastResponse || {}) },
  };
}

/**
 * @param {object} w worker doc
 * @returns {string[]} e.g. ['verified','top_rated']
 */
function computeBadges(w, rules) {
  const r = mergeRules(rules);
  const badges = [];
  if (w.verificationStatus === 'approved' && w.idVerified === true) badges.push('verified');

  const count = Number(w.ratingCount || 0);
  const avg = Number(w.ratingAvg || 0);
  if (r.topRated.enabled && count >= r.topRated.minCount && avg >= r.topRated.minAvg) badges.push('top_rated');

  if (r.mostCompleted.enabled && Number(w.completedCount || 0) >= r.mostCompleted.minCompleted) badges.push('most_completed');

  const st = w.stats || {};
  const responses = Number(st.responded || 0);
  const received = Number(st.received || 0);
  const avgMins = responses > 0 ? Number(st.responseMinutesTotal || 0) / responses : Infinity;
  const rate = received > 0 ? responses / received : 0;
  if (r.fastResponse.enabled && responses >= r.fastResponse.minResponses &&
      avgMins <= r.fastResponse.maxAvgMinutes && rate >= r.fastResponse.minResponseRate) {
    badges.push('fast_response');
  }
  return badges;
}

module.exports = { computeBadges, DEFAULT_BADGE_RULES, mergeRules };
