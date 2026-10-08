# Hark usage interface evidence

Inspected 2026-10-08. No credentials or real account payloads are included.

The official Hark web application serves these public, versioned modules:

- https://assets.hark.com/assets/BP7aVP7p.js
  SHA-256: `a28377091f6fcc792fb121e67e94a6216ff2d22650e1e36169e0aba95825dbcf`
- https://assets.hark.com/assets/D82vO-0_.js
  SHA-256: `fca0099c83f837e02988a9f3a4721348ab222f9b49183f6164b66019527f9b7a`

`BP7aVP7p.js` defines `billing.summary.query` as a GET of `/billing/summary` through a helper whose base URL is the current origin plus `/api`, with `credentials: "include"`.

`D82vO-0_.js` uses that summary in the billing query and reads the `meters.harkTokens` daily and pool fields for quota checks. It skips finite limit checks when `plan.unlimited` is true. The monthly pool is the server-reported allowance, including top-ups.

An unauthenticated GET of `https://hark.com/api/billing/summary` returned HTTP 401 and `{"error":"unauthorized"}`. The signed-in billing page rendered a monthly usage percentage. A signed-in raw response and automatic cookie import have not been tested; browser document navigation to the API was blocked by the client.

The Hark chat assistant could not verify a public developer API. This integration is based on the first-party web application, not on an AI-generated usage panel.

Validation uses synthetic quota values in `HarkPluginTests`, with stubbed HTTP and cookies on both native plugin engines. A preliminary Node VM run executed the actual bundled script and passed 19 outcome assertions for quota mapping, expired-session fallback, unlimited plans, malformed values, source-off policy, and HTTP error classification. This does not establish native-engine or live-account success.

Swift frontend syntax parsing passed for the new descriptor and test file. Provider-manifest, generated documentation, link, site-locale, and social-card checks passed. Full local native validation is pending: `make test` failed during SwiftPM manifest execution, and `make check` could not execute the pinned formatter because the local checkout/tools carry macOS quarantine metadata.
