/// Built-in word lists used by the style system (3.10).
public enum WordLists {
    /// Brands and words whose casing is fixed in Title, Sentence and As generated.
    public static let builtInProtectedWords: [String] = [
        "iPhone", "iPad", "iPod", "iMac", "iCloud", "iOS", "iPadOS", "macOS", "watchOS", "tvOS",
        "visionOS", "AirPods", "AirTag", "AirDrop", "AirPlay", "MacBook", "FaceTime", "iMessage",
        "iTunes", "iWork", "eBay", "YouTube", "GitHub", "GitLab", "PayPal", "LinkedIn", "WhatsApp",
        "TikTok", "PowerPoint", "OneDrive", "SharePoint", "OneNote", "JavaScript", "TypeScript",
        "WordPress", "DoorDash", "OpenAI", "ChatGPT", "DeepL", "WeChat", "QuickBooks", "HubSpot",
        "MailChimp", "SoundCloud", "DuckDuckGo", "StackOverflow", "PlayStation", "McDonald's",
        "IKEA", "BMW", "SBB", "UBS", "IBM", "NASA", "UPS", "DHL", "FedEx", "USPS", "PDF", "USB",
        "HDMI", "QR", "VAT", "MwSt", "TVA", "IVA", "AHV", "eID",
    ]

    /// Words kept lowercase in the middle of a Title Case phrase (3.10).
    public static func titleSmallWords(_ language: NameLanguage) -> Set<String> {
        switch language {
        case .english:
            ["a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "as", "at", "by",
             "in", "of", "on", "per", "to", "via", "vs"]
        case .french:
            ["le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "et", "ou", "à", "au",
             "aux", "en", "par", "pour", "sur", "dans", "avec", "sans", "sous"]
        case .german:
            ["der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "eines", "einem",
             "einen", "und", "oder", "aber", "im", "in", "am", "an", "auf", "aus", "bei", "mit",
             "nach", "von", "vom", "zu", "zum", "zur", "für", "über", "unter", "vor"]
        case .italian:
            ["il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "e", "ed", "o", "ma",
             "di", "del", "dello", "della", "dei", "degli", "delle", "d", "a", "al", "allo",
             "alla", "ai", "agli", "alle", "da", "dal", "in", "nel", "nella", "con", "su", "sul",
             "per", "tra", "fra"]
        case .spanish:
            ["el", "la", "los", "las", "un", "una", "unos", "unas", "y", "e", "o", "u", "ni",
             "de", "del", "a", "al", "en", "con", "por", "para", "sin", "sobre"]
        case .portuguese:
            ["o", "a", "os", "as", "um", "uma", "uns", "umas", "e", "ou", "de", "do", "da", "dos",
             "das", "em", "no", "na", "nos", "nas", "por", "para", "com", "sem", "ao", "à", "aos", "às"]
        case .dutch, .japanese, .korean, .chineseSimplified:
            []
        }
    }

    /// Filler words removed when "Remove filler words" is on (3.10).
    public static func fillerWords(_ language: NameLanguage) -> Set<String> {
        switch language {
        case .english:
            ["a", "an", "the", "and", "of", "for", "to", "in", "on", "at", "with", "from", "by",
             "my", "your", "our", "this", "that", "some"]
        case .german:
            ["der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer",
             "eines", "und", "von", "vom", "für", "mit", "im", "in", "am", "an", "zu", "zum", "zur",
             "mein", "meine", "dein", "deine", "unser", "unsere"]
        case .french:
            ["le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "et", "à", "au", "aux",
             "en", "pour", "avec", "par", "sur", "mon", "ma", "mes", "votre", "vos", "notre", "nos"]
        case .italian:
            ["il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "e", "di", "del", "della",
             "dei", "delle", "a", "al", "alla", "da", "in", "nel", "con", "per", "su", "mio", "mia"]
        case .spanish:
            ["el", "la", "los", "las", "un", "una", "unos", "unas", "y", "de", "del", "a", "al",
             "en", "con", "por", "para", "mi", "mis", "su", "sus"]
        case .portuguese:
            ["o", "a", "os", "as", "um", "uma", "e", "de", "do", "da", "dos", "das", "em", "no",
             "na", "por", "para", "com", "meu", "minha"]
        case .dutch:
            ["de", "het", "een", "en", "van", "voor", "met", "in", "op", "aan", "te", "mijn", "uw"]
        case .japanese, .korean, .chineseSimplified:
            []
        }
    }

    /// Built-in vocabulary (3.10 default "built-ins"): spelling normalizations only.
    public static let builtInVocabulary: [VocabularyRule] = [
        VocabularyRule(from: "e-mail", to: "email"),
        VocabularyRule(from: "screen shot", to: "screenshot"),
        VocabularyRule(from: "web site", to: "website"),
    ]
}

/// A whole-word replacement such as "Bill → Invoice" (3.10). Matching ignores case.
public struct VocabularyRule: Codable, Sendable, Hashable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public enum Vocabulary {
    /// Applies rules in one pass. Each word is replaced at most once, so rule chains never
    /// loop at runtime; loops are also refused when a style is saved (H7).
    public static func apply(_ rules: [VocabularyRule], to words: [String]) -> [String] {
        guard !rules.isEmpty, !words.isEmpty else { return words }
        let compiled = rules.compactMap { rule -> ([String], [String])? in
            let from = WordTokenizer.words(rule.from).map(TextFolding.caseKey)
            guard !from.isEmpty else { return nil }
            return (from, WordTokenizer.words(rule.to))
        }.sorted { $0.0.count > $1.0.count } // longest phrase first
        let keys = words.map(TextFolding.caseKey)
        var result: [String] = []
        var index = 0
        outer: while index < words.count {
            for (from, to) in compiled where index + from.count <= words.count {
                if Array(keys[index..<(index + from.count)]) == from {
                    result.append(contentsOf: to)
                    index += from.count
                    continue outer
                }
            }
            result.append(words[index])
            index += 1
        }
        return result
    }

    /// Returns the first rule that is part of a loop (A→B, B→A, or longer chains), if any.
    public static func loop(in rules: [VocabularyRule]) -> VocabularyRule? {
        let edges = rules.map { (TextFolding.caseKey($0.from.trimmed), TextFolding.caseKey($0.to.trimmed), $0) }
        var graph: [String: [String]] = [:]
        for (from, to, _) in edges { graph[from, default: []].append(to) }
        for (from, _, rule) in edges {
            var visited: Set<String> = []
            var stack = graph[from] ?? []
            while let node = stack.popLast() {
                if node == from { return rule }
                if visited.insert(node).inserted { stack.append(contentsOf: graph[node] ?? []) }
            }
        }
        return nil
    }
}

extension String {
    var trimmed: String {
        var scalars = Substring(self)
        while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }
}
