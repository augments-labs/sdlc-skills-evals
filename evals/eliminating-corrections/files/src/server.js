const http = require('http');
const { chargeTenant } = require('./billing/charge');

http.createServer((req, res) => {
  res.end(JSON.stringify(chargeTenant(req, 1000)));
}).listen(3000);
