defineProvider({
  id: "hark",
  name: "Hark Pro",
  endpoints: ["https://hark.com"],
  settings: [],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["hark.com"],
  async fetchUsage(ctx) {
    const domain = "hark.com";
    const policy = ctx.browser.availability(domain);
    if (policy === "off") throw ctx.fail.missingCredential("Hark Pro cookies are disabled.");
    let response;
    let rejected = false;
    for await (const session of ctx.browser.sessions(domain)) {
      const candidate = await ctx.http.get("https://hark.com/api/billing/summary", {
        headers: { Cookie: session.header, Accept: "application/json" },
      });
      if (candidate.status === 401) {
        rejected = true;
        ctx.browser.rejectCookie(domain, session);
        continue;
      }
      response = candidate;
      break;
    }
    if (!response) {
      throw rejected
        ? ctx.fail.authenticationExpired("Hark Pro session expired. Sign in at hark.com and refresh.")
        : ctx.fail.missingCredential("Sign in at hark.com in Chrome, or set a manual Cookie header.");
    }
    if (response.status === 403) throw ctx.fail.permissionDenied("Hark Pro denied access to the billing summary.");
    if (response.status === 429) throw ctx.fail.rateLimited("Hark Pro billing summary is rate limited.");
    if (response.status !== 200) throw ctx.fail.apiFailure(`Hark Pro returned HTTP ${response.status}.`);
    const invalid = () => {
      throw ctx.fail.parseFailure("Unexpected Hark Pro billing summary. The usage interface may have changed.");
    };
    let data;
    try {
      data = JSON.parse(response.bodyText);
    } catch {
      invalid();
    }
    if (!data || typeof data !== "object" || Array.isArray(data) || !data.plan || typeof data.plan !== "object")
      invalid();
    const plan = data.plan.name ?? data.plan.id;
    if (typeof plan !== "string" || !plan.trim()) invalid();
    const identity = { loginMethod: plan.trim() };
    if (data.plan.unlimited === true)
      return { identity, details: [{ rows: [{ label: "Usage", value: "Unlimited" }] }], dataConfidence: "exact" };
    const meter = data.meters?.harkTokens;
    if (!meter || typeof meter !== "object" || Array.isArray(meter)) invalid();
    const window = (used, limit, reset, minutes) => {
      if (typeof used !== "number" || !Number.isFinite(used) || used < 0) invalid();
      if (typeof limit !== "number" || !Number.isFinite(limit) || limit < 0) invalid();
      // A zero limit does not establish a finite allowance. Never invent a percentage for it.
      if (limit === 0) return undefined;
      let resetsAt;
      if (typeof reset === "string" && Number.isFinite(Date.parse(reset))) resetsAt = ctx.date.iso(reset);
      return { usedPercent: Math.min(100, (used / limit) * 100), windowMinutes: minutes, resetsAt };
    };
    const primary = window(meter.dailyUsed, meter.dailyLimit, meter.dailyResetsAt, 1440);
    // Calendar months have varying lengths; only the source's actual reset date is reported.
    const secondary = window(meter.poolUsed, meter.poolLimit, meter.poolResetsAt, undefined);
    if (!primary && !secondary) invalid();
    return { primary, secondary, identity, dataConfidence: "exact" };
  },
});
