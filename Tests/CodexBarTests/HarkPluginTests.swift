import Foundation
import Testing
@testable import CodexBarCore

struct HarkPluginTests {
    @Test
    func `identityless quotas cannot enter history or history based widgets`() {
        let descriptor = HarkProviderDescriptor.descriptor
        #expect(!descriptor.history.supportsPlanUtilization)
        #expect(!descriptor.metadata.burnDownWidgetSelectable)
    }

    // Synthetic values matching the fields read by Hark's public web bundle.
    static let summary = #"""
    {
      "plan": {"id":"free","name":"Hark Pro","unlimited":false},
      "meters": {"harkTokens": {
        "dailyUsed":25,"dailyLimit":100,"dailyResetsAt":"2026-10-09T00:00:00Z",
        "poolUsed":220,"poolLimit":1000,"poolResetsAt":"2026-11-01T00:00:00Z"
      }},
      "paymentMethod":{"last4":"1234"},"email":"fixture@example.com"
    }
    """#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `read only billing summary maps daily and monthly quotas`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(Self.summary, engine: engine)
        #expect(snapshot.primary?.usedPercent == 25)
        #expect(snapshot.primary?.windowMinutes == 1440)
        #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_791_504_000))
        #expect(snapshot.secondary?.usedPercent == 22)
        #expect(snapshot.secondary?.windowMinutes == nil)
        #expect(snapshot.secondary?.resetsAt == Date(timeIntervalSince1970: 1_793_491_200))
        #expect(snapshot.identity?.providerID == .hark)
        #expect(snapshot.identity?.loginMethod == "Hark Pro")
        #expect(snapshot.identity?.accountEmail == nil)
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.dataConfidence == .exact)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `explicit unlimited plans have no fabricated windows`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(
            #"{"plan":{"id":"scale","name":"Hark Pro³","unlimited":true}}"#, engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary == nil)
        #expect(snapshot.detailRow(label: "Usage")?.value == "Unlimited")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `zero daily limit and absent reset do not invent daily usage`(engine: ProviderPluginEngineKind) async throws {
        let body = Self.summary.replacingOccurrences(of: #""dailyLimit":100"#, with: #""dailyLimit":0"#)
            .replacingOccurrences(of: "2026-11-01T00:00:00Z", with: "invalid")
        let snapshot = try await Self.fetch(body, engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.secondary?.usedPercent == 22)
        #expect(snapshot.secondary?.resetsAt == nil)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `exhausted usage is clamped and plan IDs remain usable`(engine: ProviderPluginEngineKind) async throws {
        let body = Self.summary.replacingOccurrences(of: #""dailyUsed":25"#, with: #""dailyUsed":125"#)
            .replacingOccurrences(of: #","name":"Hark Pro""#, with: "")
        let snapshot = try await Self.fetch(body, engine: engine)
        #expect(snapshot.primary?.usedPercent == 100)
        #expect(snapshot.identity?.loginMethod == "free")
    }

    @Test(arguments: ["{}", "<html>Sign in</html>",
                      #"{"plan":{"id":"free"},"meters":null}"#], BundledPluginTestSupport.engines)
    func `missing quota data fails instead of displaying zero`(body: String, engine: ProviderPluginEngineKind) async {
        await CookiePluginFixtures.expectFailure(.parseFailure) { try await Self.fetch(body, engine: engine) }
    }

    @Test(arguments: ["-1", "null", "true", "\"25\"", "1e999"], BundledPluginTestSupport.engines)
    func `invalid counts fail closed`(value: String, engine: ProviderPluginEngineKind) async {
        let body = Self.summary.replacingOccurrences(of: #""dailyUsed":25"#, with: "\"dailyUsed\":\(value)")
        await CookiePluginFixtures.expectFailure(.parseFailure) { try await Self.fetch(body, engine: engine) }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `expired sessions keep authentication recovery distinct from access denials`(
        engine: ProviderPluginEngineKind) async
    {
        await CookiePluginFixtures.expectFailure(.authenticationExpired) {
            try await Self.fetch(#"{"error":"unauthorized"}"#, engine: engine, status: 401)
        }
        await CookiePluginFixtures.expectFailure(.permissionDenied) {
            try await Self.fetch("Forbidden", engine: engine, status: 403)
        }
        await CookiePluginFixtures.expectFailure(.rateLimited) {
            try await Self.fetch("Slow down", engine: engine, status: 429)
        }
        await CookiePluginFixtures.expectFailure(.apiFailure) {
            try await Self.fetch("Unavailable", engine: engine, status: 503)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `automatic cookies reject an expired candidate before accepting another profile`(
        engine: ProviderPluginEngineKind) async throws
    {
        let attempts = LockIsolated(0)
        let rejected = LockIsolated<[String]>([])
        let runtime = try BundledPluginTestSupport.runtime("hark", engine: engine, transport: ProviderHTTPTransportHandler {
            request in
            let expired = request.value(forHTTPHeaderField: "Cookie") == "session=expired"
            return try CookiePluginFixtures.response(request, body: Self.summary, status: expired ? 401 : 200)
        })
        let snapshot = try await runtime.fetchUsage(cookieSessionResolver: { domain, _ in
            #expect(domain == "hark.com")
            attempts.setValue(attempts.value + 1)
            guard attempts.value <= 2 else { return nil }
            let id = attempts.value == 1 ? "expired" : "valid"
            return ProviderPluginCookieSession(
                header: "session=\(id)", source: "Chrome", origin: "https://hark.com", id: id)
        }, cookieSessionInvalidator: { domain, id in
            #expect(domain == "hark.com")
            rejected.setValue(rejected.value + [id])
        })
        #expect(snapshot.primary?.usedPercent == 25)
        #expect(attempts.value == 2)
        #expect(rejected.value == ["expired"])
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `disabled cookies never access transport`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime("hark", engine: engine, transport: ProviderHTTPTransportHandler {
            request in
            Issue.record("Disabled cookies reached transport")
            return try CookiePluginFixtures.response(request, body: Self.summary)
        })
        await CookiePluginFixtures.expectFailure(.missingCredential) {
            try await runtime.fetchUsage(cookieSource: .off, cookieResolver: { _, _ in "session=fixture" })
        }
    }

    private static func fetch(
        _ body: String,
        engine: ProviderPluginEngineKind,
        status: Int = 200) async throws -> UsageSnapshot
    {
        let runtime = try BundledPluginTestSupport.runtime("hark", engine: engine, transport: ProviderHTTPTransportHandler {
            request in
            #expect(request.url?.absoluteString == "https://hark.com/api/billing/summary")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=fixture")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            return try CookiePluginFixtures.response(request, body: body, status: status)
        })
        return try await runtime.fetchUsage(cookieSource: .manual, cookieResolver: { _, _ in "session=fixture" })
    }
}
