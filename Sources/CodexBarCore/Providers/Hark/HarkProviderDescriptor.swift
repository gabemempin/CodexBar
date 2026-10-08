import Foundation

public enum HarkProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .hark,
        displayName: "Hark Pro",
        sessionLabel: "Daily",
        weeklyLabel: "Monthly",
        dashboardURL: "https://hark.com/settings/billing",
        color: .init(hex: 0xFF6B35),
        confetti: [0xFF6B35, 0xF4E8DB, 0x262626],
        noDataMessage: "Hark Pro reports usage limits, not a cost history.",
        aliases: ["hark-pro"],
        webSource: .init(
            settingsSection: .init(HarkProviderSettingsKey.self, cookieSettings: CookieProviderSettings.self),
            browserCookieOrder: BrowserCookieImportSupport.chromeOnly(
                reason: "Hark Pro browser sessions are imported from Chrome."),
            browserSupportExemption: { _, _, settings in settings?.hark?.cookieSource == .manual },
            resolveValues: { $0.settings?.hark?.cookieSource == .off ? nil : .init() },
            field: .init(
                id: "hark-cookie-header",
                title: "Cookie header",
                subtitle: "Paste the Cookie header from a signed-in hark.com billing summary request.",
                placeholder: "Cookie: …",
                action: (id: "hark-open-billing", title: "Open Hark Billing", url: "https://hark.com/settings/billing")),
            picker: .init(
                id: "hark-cookie-source",
                allowsOff: true,
                auto: .localized("Automatic imports browser cookies."),
                manual: .localized("Paste a Cookie header captured from %@.", argument: "hark.com"),
                off: .localized("%@ cookies are disabled.", argument: "Hark Pro")),
            detailLine: "web",
            loginURL: "https://hark.com"))
}

public enum HarkProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.hark
    public typealias Section = CookieProviderSettings
}

extension ProviderSettingsSnapshot {
    public var hark: CookieProviderSettings? {
        self[HarkProviderSettingsKey.self]
    }
}
