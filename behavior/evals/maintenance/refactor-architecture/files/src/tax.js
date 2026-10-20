// Rates are keyed by the canonical UPPERCASE region code.
const RATES = {
  DE: 0.19, FR: 0.20, GB: 0.20, ES: 0.21, IT: 0.22,
  'US-CA': 0.0725, 'US-NY': 0.08875,
};
function rateFor(region) { return RATES[region]; }
module.exports = { rateFor, RATES };
