// Unit prices are integer cents: multiplying by quantity stays exact,
// where floats would drift.
const catalogue = new Map([
  ['widget', 1999],
  ['gizmo', 4599],
]);

function unitPrice(item) {
  const price = catalogue.get(item);
  if (price === undefined) throw new Error(`unknown item: ${item}`);
  return price;
}

// Bulk orders ship in crates of ten; a partial crate still ships whole.
function cratesFor(quantity) {
  return Math.ceil(quantity / 10);
}

// Volume discounts are applied to the order as a whole, not per line: the
// tiers are a function of how many units the order carries.
const volumeTiers = [
  { minimumQuantity: 500, discountRate: 0.15 },
  { minimumQuantity: 100, discountRate: 0.08 },
];

function volumeDiscountRate(quantity) {
  const tier = volumeTiers.find((candidate) => quantity >= candidate.minimumQuantity);
  return tier ? tier.discountRate : 0;
}

function orderTotal(item, quantity) {
  const grossTotal = unitPrice(item) * quantity;
  // The discount is rounded to whole cents: only whole cents are charged.
  return Math.round(grossTotal * (1 - volumeDiscountRate(quantity)));
}

module.exports = { unitPrice, cratesFor, volumeDiscountRate, orderTotal };
