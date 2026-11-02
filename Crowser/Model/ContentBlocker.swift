import WebKit

/// A small, conservative ad and tracker blocklist compiled into a WebKit content rule list.
/// Only third-party loads from known ad/tracking networks are blocked, so sites themselves keep working.
enum ContentBlocker {
    static let storageKey = "crowser.blockTrackers"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }

    private static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "amazon-adsystem.com", "adnxs.com", "taboola.com", "outbrain.com", "criteo.com", "criteo.net",
        "scorecardresearch.com", "quantserve.com", "pubmatic.com", "rubiconproject.com", "openx.net",
        "moatads.com", "adsrvr.org", "casalemedia.com", "33across.com", "sharethrough.com", "teads.tv",
        "smartadserver.com", "yieldmo.com", "bidswitch.net", "indexww.com", "hotjar.com", "mouseflow.com",
        "advertising.com", "adform.net", "serving-sys.com", "zemanta.com", "revcontent.com", "mgid.com",
        "google-analytics.com", "googletagservices.com", "connect.facebook.net", "ads-twitter.com",
        "analytics.tiktok.com", "bat.bing.com", "clarity.ms", "segment.io", "mixpanel.com", "amplitude.com",
        "nr-data.net", "chartbeat.com", "chartbeat.net", "parsely.com", "quantcount.com", "krxd.net",
        "bluekai.com", "demdex.net", "everesttech.net", "rlcdn.com", "agkn.com", "tapad.com", "lijit.com",
        "sovrn.com", "gumgum.com", "triplelift.com", "contextweb.com", "spotxchange.com", "springserve.com",
        "adsafeprotected.com", "doubleverify.com", "permutive.com", "id5-sync.com", "liadm.com",
    ]

    static let cookieKey = "crowser.hideCookieBanners"

    /// Consent-popup services and the containers they draw into.
    private static let cookieDomains = [
        "cookielaw.org", "onetrust.com", "cookiebot.com", "consensu.org", "trustarc.com", "didomi.io",
        "usercentrics.eu", "privacy-mgmt.com", "cookiepro.com", "iubenda.com", "termly.io", "osano.com",
        "consentmanager.net", "cookieyes.com", "cookie-script.com", "cookiefirst.com", "civiccomputing.com",
    ]

    private static let cookieSelectors = [
        "#onetrust-consent-sdk", "#onetrust-banner-sdk", "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
        ".fc-consent-root", "#qc-cmp2-container", "#truste-consent-track", "#didomi-host", "#usercentrics-root",
        "#cookiescript_injected", ".cky-consent-container", ".cc-window", "#cookie-law-info-bar", "#cmpbox", "#cmpbox2",
        "div[id^='sp_message_container']", ".osano-cm-window", "#ccc",
    ]

    static func compileCookieRules() async -> WKContentRuleList? {
        var rules: [[String: Any]] = cookieDomains.map { domain in
            [
                "trigger": ["url-filter": "^https?://[^/]*" + NSRegularExpression.escapedPattern(for: domain)],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": cookieSelectors.joined(separator: ", ")],
        ])
        return await compile(rules, identifier: "crowser.cookies.v1")
    }

    private static func compile(_ rules: [[String: Any]], identifier: String) async -> WKContentRuleList? {
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let ruleStore: WKContentRuleListStore? = WKContentRuleListStore.default()
        let list: WKContentRuleList? = try? await ruleStore?.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: json
        )
        return list
    }

    static func compile() async -> WKContentRuleList? {
        let rules: [[String: Any]] = domains.map { domain in
            [
                "trigger": [
                    "url-filter": "^https?://[^/]*" + NSRegularExpression.escapedPattern(for: domain),
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let ruleStore: WKContentRuleListStore? = WKContentRuleListStore.default()
        let list: WKContentRuleList? = try? await ruleStore?.compileContentRuleList(
            forIdentifier: "crowser.blocklist.v2",
            encodedContentRuleList: json
        )
        return list
    }
}
