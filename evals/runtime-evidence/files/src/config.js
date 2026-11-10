// Settings for the service: config/default.json, then the environment.
const path = require('node:path');
const defaults = require(path.join(__dirname, '..', 'config', 'default.json'));

function load(env = process.env) {
  const config = { ...defaults };
  if (env.HTTP_TIMEOUT_MS) config.httpTimeoutMs = Number(env.HTTP_TIMEOUT_MS);
  return config;
}

module.exports = { load };
