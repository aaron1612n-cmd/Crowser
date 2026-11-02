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
    ]

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
            forIdentifier: "crowser.blocklist.v1",
            encodedContentRuleList: json
        )
        return list
    }
}
