/// Company names for download domains (3.8 Basic naming "built-in alias list").
public enum DomainAliases {
    static let aliases: [String: String] = [
        "amazon": "Amazon", "apple": "Apple", "icloud": "Apple", "google": "Google", "microsoft": "Microsoft",
        "github": "GitHub", "paypal": "PayPal", "ebay": "eBay", "ikea": "IKEA", "booking": "Booking.com",
        "airbnb": "Airbnb", "uber": "Uber", "netflix": "Netflix", "spotify": "Spotify", "zalando": "Zalando",
        "galaxus": "Galaxus", "digitec": "Digitec", "migros": "Migros", "coop": "Coop", "post": "Post",
        "swisscom": "Swisscom", "sunrise": "Sunrise", "salt": "Salt", "sbb": "SBB", "lufthansa": "Lufthansa",
        "swiss": "Swiss", "easyjet": "easyJet", "ryanair": "Ryanair", "bahn": "Deutsche Bahn",
        "deutschebahn": "Deutsche Bahn", "sncf-connect": "SNCF", "sncf": "SNCF", "trenitalia": "Trenitalia",
        "renfe": "Renfe", "dropbox": "Dropbox", "linkedin": "LinkedIn", "twitter": "X", "x": "X",
        "facebook": "Facebook", "instagram": "Instagram", "whatsapp": "WhatsApp", "slack": "Slack",
        "zoom": "Zoom", "notion": "Notion", "figma": "Figma", "adobe": "Adobe", "canva": "Canva",
        "dhl": "DHL", "ups": "UPS", "fedex": "FedEx", "usps": "USPS", "laposte": "La Poste",
        "deutschepost": "Deutsche Post", "aliexpress": "AliExpress", "temu": "Temu", "etsy": "Etsy",
        "steam": "Steam", "steampowered": "Steam", "playstation": "PlayStation", "nintendo": "Nintendo",
        "telekom": "Telekom", "vodafone": "Vodafone", "orange": "Orange", "o2": "O2", "tmobile": "T-Mobile",
        "t-mobile": "T-Mobile", "verizon": "Verizon", "att": "AT&T", "ubs": "UBS", "postfinance": "PostFinance",
        "revolut": "Revolut", "wise": "Wise", "n26": "N26", "stripe": "Stripe", "klarna": "Klarna",
        "helsana": "Helsana", "css": "CSS", "axa": "AXA", "allianz": "Allianz", "zurich": "Zurich",
        "admin": "Swiss Confederation", "elster": "ELSTER", "irs": "IRS", "hmrc": "HMRC", "gov": "Government",
    ]

    /// Labels that never name a company ("www", "mail" …).
    static let ignoredLabels: Set<String> = ["www", "www2", "mail", "m", "app", "apps", "cdn", "static", "download",
                                             "downloads", "dl", "files", "file", "secure", "my", "account", "accounts",
                                             "login", "drive", "docs", "s3", "storage", "media", "assets", "img", "images"]

    /// Two-label public suffixes, so "example.co.uk" yields "example".
    static let secondLevelSuffixes: Set<String> = ["co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au",
                                                   "co.jp", "ne.jp", "or.jp", "com.br", "com.mx", "co.nz", "co.za",
                                                   "com.cn", "com.tw", "co.kr", "com.sg", "co.in", "com.tr", "com.ar"]

    /// The registrable label of a host: "mail.example.co.uk" → "example".
    public static func registrableLabel(_ host: String) -> String? {
        var labels = host.lowercased().split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard labels.count >= 2 else { return labels.first }
        if labels.count >= 3, secondLevelSuffixes.contains(labels.suffix(2).joined(separator: ".")) {
            labels.removeLast(2)
        } else {
            labels.removeLast()
        }
        return labels.last { !ignoredLabels.contains($0) } ?? labels.last
    }

    /// The company for a download domain: from the alias list, otherwise the registrable
    /// label capitalized ("acme-tools.ch" → "Acme Tools").
    public static func source(forDomain host: String) -> String? {
        guard let label = registrableLabel(host) else { return nil }
        if let alias = aliases[label] { return alias }
        let words = label.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let name = words.joined(separator: " ")
        return name.count >= 2 ? name : nil
    }

    /// True when `source` is what this domain stands for (alias or label), for validation (3.9).
    public static func matches(source: String, domain: String) -> Bool {
        guard let expected = Self.source(forDomain: domain) else { return false }
        return TextFolding.key(expected) == TextFolding.key(source)
    }
}
