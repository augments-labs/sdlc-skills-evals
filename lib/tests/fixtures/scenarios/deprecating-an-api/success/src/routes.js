const { legacyProfile } = require('./profile');

// GET /v1/profile returns the flattened shape. The deprecation marker is the
// header pair the HTTP protocol defines, so a caller that reads the response
// sees it without reading a changelog.
function profileResponse(user) {
  return {
    status: 200,
    headers: {
      Deprecation: '@1688169599',
      Sunset: 'Sun, 30 Jun 2024 23:59:59 GMT',
      Link: '<https://example.invalid/docs/profile-v2>; rel="deprecation"',
    },
    body: legacyProfile(user),
  };
}

module.exports = { profileResponse };
