// The authenticated session for a request. The tenant a request acts for is
// the session's tenant; nothing the client sends can change it.
function sessionFor(req) {
  return { userId: req.user.id, tenantId: req.user.tenantId };
}

module.exports = { sessionFor };
