// Feature flags are re-read on every request from config/flags.json, so a
// flag can be turned off without a deploy.
const fs = require('fs');
const path = require('path');

function flag(name) {
  const flags = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config', 'flags.json'), 'utf8'));
  const entry = flags[name];
  return entry ? Boolean(entry.enabled) : false;
}

module.exports = { flag };
