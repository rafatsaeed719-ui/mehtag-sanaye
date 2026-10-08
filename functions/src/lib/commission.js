'use strict';
/**
 * حساب العمولة — يتم على السيرفر فقط.
 * نحسب بالقرش (أعداد صحيحة) لتجنب أخطاء الكسور العشرية.
 */

const MAX_SERVICE_PRICE = 1000000; // مليون جنيه حد أقصى للحماية من الإدخال الخاطئ
const MAX_RATE = 0.3;

class CommissionError extends Error {
  constructor(code) { super(code); this.code = code; }
}

function validateRate(rate) {
  if (typeof rate !== 'number' || !Number.isFinite(rate) || rate < 0 || rate > MAX_RATE) {
    throw new CommissionError('invalid-rate');
  }
  return rate;
}

/**
 * @param {number} price قيمة الخدمة المتفق عليها بالجنيه
 * @param {number} rate نسبة العمولة (0.05 = 5%)
 * @returns {{price:number, rate:number, commission:number, pricePiasters:number, commissionPiasters:number}}
 */
function computeCommission(price, rate) {
  if (typeof price === 'string') price = Number(price);
  if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0 || price > MAX_SERVICE_PRICE) {
    throw new CommissionError('invalid-price');
  }
  validateRate(rate);
  const pricePiasters = Math.round(price * 100);
  const commissionPiasters = Math.round(pricePiasters * rate);
  return {
    price: pricePiasters / 100,
    rate,
    commission: commissionPiasters / 100,
    pricePiasters,
    commissionPiasters,
  };
}

/** يجمع مبالغ بالجنيه بدقة القرش */
function sumMoney(values) {
  return values.reduce((acc, v) => acc + Math.round(Number(v || 0) * 100), 0) / 100;
}

module.exports = { computeCommission, sumMoney, validateRate, CommissionError, MAX_SERVICE_PRICE, MAX_RATE };
