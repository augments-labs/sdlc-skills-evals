# notify-service

Sends notifications to subscriber endpoints.

- `src/http/client.js`: the outgoing HTTP client and its timeout
- `src/config.js`: reads `config/default.json`
- `src/text/slug.js`: turns a title into a URL slug; `src/text/slug.old.js`
  is the version it replaced
