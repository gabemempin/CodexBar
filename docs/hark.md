---
summary: "Hark Pro daily and monthly usage from its read-only web billing summary."
read_when:
  - Configuring Hark Pro usage tracking
  - Debugging Hark Pro browser sessions or billing summary parsing
provider_id: hark
provider_name: Hark Pro
provider_source: Browser cookies → daily and monthly usage limits
plugin_scope: Read-only billing summary; daily ceiling and monthly token pool
---

# Hark Pro

Enable **Hark Pro** in Settings → Providers. Sign in at [hark.com](https://hark.com) in Chrome for
**Automatic** cookie import, or select **Manual** and paste the Cookie request header from a signed-in
`https://hark.com/api/billing/summary` request. **Off** disables cookie access. Linux requires a manual header.
Treat this header as a credential; never include it in issues, screenshots, or pull requests.

The bundled `hark.js` plugin performs only `GET https://hark.com/api/billing/summary`. It does not send chat
messages, refresh AI-generated panels, or call checkout, subscription, or auto-top-up mutations.
Hark does not publish a developer usage API; this is the private read-only endpoint used by its own web app,
and its contract can change. Hark's [official usage guide](https://hark.com/using-hark) describes usage caps
and subscription tiers.

The web app's billing module calls `/billing/summary` relative to `/api` with session cookies. Its quota
logic reads `meters.harkTokens.dailyUsed`, `dailyLimit`, `dailyResetsAt`, `poolUsed`, `poolLimit`, and
`poolResetsAt`. CodexBar maps these to Daily and Monthly bars, preserving reported reset timestamps and
the plan's `name` (falling back to `id`). The pool reflects the server's allowance, including any top-ups;
CodexBar does not assume a fixed plan allowance or a 30-day month. Explicit unlimited plans show
"Unlimited" without fabricated quota bars. Zero limits omit that window; missing or invalid quota data
produces a parse error instead of displaying 0% used.

Expired sessions (`401`) are rejected so Automatic mode can try another Chrome profile. Rate limits,
access denials, and response-format changes have distinct errors. Only the `hark.com` origin receives
session cookies. No account profile or payment details are requested or displayed.
