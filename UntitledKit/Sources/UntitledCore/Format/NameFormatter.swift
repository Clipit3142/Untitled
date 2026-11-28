import Foundation

/// Inputs to formatting other than fields and style.
public struct FormatContext: Sendable, Hashable {
    /// The resolved name language (the style's fixed language, or the content's).
    public var language: NameLanguage
    public var customKinds: [CustomKind]
    /// The file's current extension as found by `FileExtension.split`, or nil.
    public var fileExtension: String?
    /// Selects the screenshot template.
    public var isScreenshot: Bool
    /// The collision counter, 2…99, or nil for no suffix (3.13).
    public var collisionNumber: Int?

    public init(
        language: NameLanguage = .english,
        customKinds: [CustomKind] = [],
        fileExtension: String? = nil,
        isScreenshot: Bool = false,
        collisionNumber: Int? = nil
    ) {
        self.language = language
        self.customKinds = customKinds
        self.fileExtension = fileExtension
        self.isScreenshot = isScreenshot
        self.collisionNumber = collisionNumber
    }
}

/// One token as it appears in the final name.
public struct RenderedPart: Sendable, Hashable, Codable {
    public var token: TokenKind
    public var text: String
    public var required: Bool

    public init(token: TokenKind, text: String, required: Bool) {
        self.token = token
        self.text = text
        self.required = required
    }
}

/// The result of formatting.
public struct FormattedName: Sendable, Hashable {
    /// The base name, including any collision suffix.
    public var base: String
    /// Base plus extension.
    public var fileName: String
    /// Tokens present in the name, in order.
    public var parts: [RenderedPart]
    /// Required tokens that ended up empty after the guards (3.9 confidence).
    public var missingRequiredTokens: [TokenKind]
    /// Subject words before any guard ran.
    public var subjectWordsBefore: Int
    /// Subject words removed by the PII guard and never-include list.
    public var subjectWordsRemovedByGuards: Int
    /// Tokens removed to fit the length limits, in removal order.
    public var droppedTokens: [TokenKind]

    public init(base: String, fileName: String, parts: [RenderedPart], missingRequiredTokens: [TokenKind],
                subjectWordsBefore: Int, subjectWordsRemovedByGuards: Int, droppedTokens: [TokenKind]) {
        self.base = base
        self.fileName = fileName
        self.parts = parts
        self.missingRequiredTokens = missingRequiredTokens
        self.subjectWordsBefore = subjectWordsBefore
        self.subjectWordsRemovedByGuards = subjectWordsRemovedByGuards
        self.droppedTokens = droppedTokens
    }
}

/// Builds names from fields with a style (3.10 "Formatter"). Pure: the same inputs always
/// give the same output.
public enum NameFormatter {
    public static func format(_ fields: NameFields, style: NamingStyle, context: FormatContext) -> FormattedName {
        var builder = Builder(fields: fields, style: style, context: context)
        return builder.build()
    }
}

// MARK: - Implementation

private struct Piece {
    var kind: TokenKind
    var required: Bool
    var words: [String]
    /// For the date token: the time word, kept apart so it can be dropped before the date is cut.
    var timeWord: String?
    var isGenerated: Bool

    var isEmpty: Bool { words.isEmpty && timeWord == nil }
}

private struct Builder {
    let fields: NameFields
    let style: NamingStyle
    let context: FormatContext
    let caser: CaseTransformer
    let banned: NeverInclude
    let partSeparator: String
    let wordSeparator: String
    let suffix: String

    var subjectWordsBefore = 0
    var subjectWordsRemovedByGuards = 0
    var droppedTokens: [TokenKind] = []

    init(fields: NameFields, style: NamingStyle, context: FormatContext) {
        self.fields = fields
        self.style = style
        self.context = context
        self.caser = CaseTransformer(mode: style.caseMode, language: context.language, protectedWords: style.protectedWords)
        self.banned = NeverInclude(style.neverInclude)
        self.partSeparator = style.partSeparator.rawValue
        self.wordSeparator = style.effectiveWordSeparator
        if let n = context.collisionNumber {
            self.suffix = style.suffixSeparator + String(n)
        } else {
            self.suffix = ""
        }
    }

    mutating func build() -> FormattedName {
        let template = style.template(forScreenshot: context.isScreenshot)
        var pieces = template.map { makePiece($0) }
        pieces = removeCrossTokenPII(pieces)
        let missing = template.indices.filter { template[$0].required && pieces[$0].isEmpty }.map { template[$0].kind }

        if !pieces.contains(where: { !$0.isEmpty }) {
            pieces = fallbackPieces()
        }

        let ext = FileExtension.render(context.fileExtension, case: style.extensionCase)
        let extBytes = ext.map { $0.utf8.count + 1 } ?? 0
        let suffixCount = suffix.count
        let suffixBytes = suffix.utf8.count
        let maxLength = style.maxLength

        let snapshot = self
        var dropped: [TokenKind] = []
        func fitBoth(_ input: [Piece]) -> [Piece] {
            let byLength = snapshot.fit(input) { snapshot.render($0).count + suffixCount <= maxLength }
            let byBytes = snapshot.fit(byLength.pieces) {
                snapshot.render($0).utf8.count + suffixBytes + extBytes <= Defaults.maxFileNameBytes
            }
            dropped += byLength.dropped + byBytes.dropped
            return byBytes.pieces
        }
        pieces = fitBoth(pieces)
        // Dropping a token can bring two digit groups next to each other; check again.
        let rechecked = removeCrossTokenPII(pieces)
        if rechecked.map(\.words) != pieces.map(\.words) {
            pieces = fitBoth(rechecked)
        }
        if !pieces.contains(where: { !$0.isEmpty }) {
            pieces = fitBoth(fallbackPieces())
        }

        droppedTokens = dropped
        let base = render(pieces) + suffix
        let parts = pieces.filter { !$0.isEmpty }.map {
            RenderedPart(token: $0.kind, text: renderPiece($0), required: $0.required)
        }
        let fileName = ext.map { base + "." + $0 } ?? base
        return FormattedName(
            base: base,
            fileName: fileName,
            parts: parts,
            missingRequiredTokens: missing,
            subjectWordsBefore: subjectWordsBefore,
            subjectWordsRemovedByGuards: subjectWordsRemovedByGuards,
            droppedTokens: droppedTokens
        )
    }

    // MARK: Step 1–6: pieces

    mutating func makePiece(_ token: TemplateToken) -> Piece {
        switch token.kind {
        case .date:
            guard let date = fields.date else { return Piece(kind: .date, required: token.required, words: [], isGenerated: false) }
            let rendered = DateRenderer.words(date, format: style.dateFormat, time: style.timeFormat, language: context.language)
            var dateWords = rendered
            var time: String?
            if style.timeFormat != .off, style.dateFormat.hasDay, date.hasTime, let last = dateWords.popLast() {
                time = last
            }
            let cased = caseDateWords(dateWords).map { characterOptions($0) }
            return Piece(kind: .date, required: token.required, words: cased, timeWord: time, isGenerated: false)
        case .text:
            let text = Sanitizer.sanitizeComponent(token.text ?? "", options: style.characters)
            if text.isEmpty || banned.containsBannedWord(text) {
                return Piece(kind: .text, required: token.required, words: [], isGenerated: false)
            }
            return Piece(kind: .text, required: token.required, words: [text], isGenerated: false)
        case .kind:
            let label = fields.kind.label(in: context.language, customKinds: context.customKinds)
            var words = WordTokenizer.words(label)
            words = Vocabulary.apply(style.vocabulary, to: words)
            words = banned.remove(from: words)
            return finishedPiece(.kind, token.required, words, generated: false)
        case .source:
            var words = guardedWords(fields.source, vocabulary: true).words
            words = removeConsecutiveDuplicates(words)
            words = Array(words.prefix(Defaults.sourceMaxWords))
            return finishedPiece(.source, token.required, words, generated: true)
        case .subject:
            let guarded = guardedWords(fields.subject, vocabulary: true)
            subjectWordsBefore = guarded.before
            subjectWordsRemovedByGuards = guarded.removedByGuards
            var words = removeConsecutiveDuplicates(guarded.words)
            words = removeRepeatsOfOtherTokens(words)
            if style.removeFillerWords {
                let filler = WordLists.fillerWords(context.language)
                let kept = words.filter { !filler.contains(TextFolding.caseKey($0)) }
                if !kept.isEmpty { words = kept }
            }
            words = Array(words.prefix(style.subjectWords))
            return finishedPiece(.subject, token.required, words, generated: true)
        case .app:
            let words = guardedWords(fields.app, vocabulary: false).words
            return finishedPiece(.app, token.required, words, generated: true)
        case .original:
            let words = guardedWords(fields.original, vocabulary: false).words
            return finishedPiece(.original, token.required, words, generated: true)
        }
    }

    /// PII guard on the raw text, then words, vocabulary and never-include.
    func guardedWords(_ text: String?, vocabulary: Bool) -> (words: [String], before: Int, removedByGuards: Int) {
        guard let text, !text.isEmpty else { return ([], 0, 0) }
        let before = WordTokenizer.words(text).count
        let redacted = PIIGuard.redact(text).text
        var words = WordTokenizer.words(redacted)
        let afterPII = words.count
        if vocabulary { words = Vocabulary.apply(style.vocabulary, to: words) }
        let beforeBanned = words.count
        words = banned.remove(from: words)
        let removed = max(0, before - afterPII) + max(0, beforeBanned - words.count)
        return (words, before, min(before, removed))
    }

    /// Case, character options and a per-token PII check after joining.
    func finishedPiece(_ kind: TokenKind, _ required: Bool, _ words: [String], generated: Bool) -> Piece {
        var cased = caser.apply(words).map { characterOptions($0) }.filter { !$0.isEmpty }
        cased = cased.filter { !banned.containsBannedWord($0) }
        if generated, PIIGuard.containsPII(cased.joined(separator: wordSeparator)) {
            cased = cased.filter { word in !word.contains(where: \.isDecimalDigit) }
        }
        return Piece(kind: kind, required: required, words: cased, isGenerated: generated)
    }

    func characterOptions(_ word: String) -> String {
        let applied = Sanitizer.applyCharacterOptions(word, style.characters)
        return Sanitizer.sanitizeBase(applied, partSeparator: partSeparator, wordSeparator: wordSeparator, options: style.characters)
    }

    func caseDateWords(_ words: [String]) -> [String] {
        words.enumerated().map { index, word in
            guard word.contains(where: \.isLetter) else { return word }
            switch style.caseMode {
            case .lowercase: return word.lowercased()
            case .uppercase: return word.uppercased()
            case .asGenerated: return word
            case .sentence: return index == 0 ? capitalizeFirst(word) : word.lowercased()
            case .title, .camel, .pascal: return capitalizeFirst(word)
            }
        }
    }

    func capitalizeFirst(_ word: String) -> String {
        guard let first = word.first, !first.isDecimalDigit else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    func removeConsecutiveDuplicates(_ words: [String]) -> [String] {
        var result: [String] = []
        for word in words where result.last.map({ TextFolding.key($0) != TextFolding.key(word) }) ?? true {
            result.append(word)
        }
        return result
    }

    /// Removes subject words that repeat the kind or the source, when those tokens are in
    /// the template. If that would leave nothing, the subject is kept as it was.
    func removeRepeatsOfOtherTokens(_ words: [String]) -> [String] {
        let template = style.template(forScreenshot: context.isScreenshot)
        var repeated: Set<String> = []
        if template.contains(where: { $0.kind == .kind }) {
            let label = fields.kind.label(in: context.language, customKinds: context.customKinds)
            for word in WordTokenizer.words(label) { repeated.insert(TextFolding.key(word)) }
        }
        if template.contains(where: { $0.kind == .source }), let source = fields.source {
            for word in WordTokenizer.words(PIIGuard.redact(source).text) { repeated.insert(TextFolding.key(word)) }
        }
        guard !repeated.isEmpty else { return words }
        let kept = words.filter { !repeated.contains(TextFolding.key($0)) }
        return kept.isEmpty ? words : kept
    }

    /// When digit groups from different generated tokens line up into something the PII
    /// guard would remove, digit-only words are removed from the generated tokens.
    func removeCrossTokenPII(_ pieces: [Piece]) -> [Piece] {
        let probe = pieces.filter { !$0.isEmpty }.map { piece -> String in
            piece.isGenerated ? renderPiece(piece) : "X"
        }.joined(separator: partSeparator)
        guard PIIGuard.containsPII(probe) else { return pieces }
        return pieces.map { piece in
            guard piece.isGenerated else { return piece }
            var copy = piece
            copy.words = piece.words.filter { word in !word.allSatisfy { $0.isDecimalDigit || !$0.isLetter } }
            return copy
        }
    }

    /// "File" in the name language when nothing else is left (3.10 step 9), with the date in
    /// front when the template has one and a date is known.
    func fallbackPieces() -> [Piece] {
        var candidates = [context.language.fileWord, "File", "Untitled", "Document", "N"]
        if style.characters.asciiOnly { candidates.removeFirst() }
        let word = candidates.first { candidate in
            !banned.containsBannedWord(candidate) && !characterOptions(candidate).isEmpty
        } ?? "N"
        let cased = caser.apply([word]).map { characterOptions($0) }.filter { !$0.isEmpty }
        var pieces: [Piece] = []
        let template = style.template(forScreenshot: context.isScreenshot)
        if let dateToken = template.first(where: { $0.kind == .date }), let date = fields.date {
            let words = DateRenderer.words(date.dayOnly, format: style.dateFormat, time: .off, language: context.language)
            pieces.append(Piece(kind: .date, required: dateToken.required,
                                words: caseDateWords(words).map { characterOptions($0) }, isGenerated: false))
        }
        pieces.append(Piece(kind: .subject, required: true, words: cased.isEmpty ? ["N"] : cased, isGenerated: false))
        return pieces
    }

    // MARK: Step 5 and 7: render

    func renderPiece(_ piece: Piece) -> String {
        var text = piece.words.joined(separator: wordSeparator)
        if let time = piece.timeWord {
            let joint = wordSeparator.isEmpty ? "-" : wordSeparator
            text = text.isEmpty ? time : text + joint + time
        }
        return text
    }

    func render(_ pieces: [Piece]) -> String {
        let joined = pieces.filter { !$0.isEmpty }.map { renderPiece($0) }.filter { !$0.isEmpty }.joined(separator: partSeparator)
        return Sanitizer.sanitizeBase(joined, partSeparator: partSeparator, wordSeparator: wordSeparator, options: style.characters)
    }

    // MARK: Step 8: fit

    func fit(_ input: [Piece], fits: ([Piece]) -> Bool) -> (pieces: [Piece], dropped: [TokenKind]) {
        var pieces = input
        var droppedTokens: [TokenKind] = []
        if fits(pieces) { return (pieces, droppedTokens) }

        // 1. Drop optional tokens: Original, Text, App, Source, Kind, Date.
        for kind in [TokenKind.original, .text, .app, .source, .kind, .date] {
            while !fits(pieces),
                  let index = pieces.lastIndex(where: { $0.kind == kind && !$0.required && !$0.isEmpty }) {
                pieces[index].words = []
                pieces[index].timeWord = nil
                droppedTokens.append(kind)
            }
            if fits(pieces) { return (pieces, droppedTokens) }
        }

        // 2. Trim subject words from the end, keeping at least one.
        while !fits(pieces), let index = pieces.firstIndex(where: { $0.kind == .subject && $0.words.count > 1 }) {
            pieces[index].words.removeLast()
        }
        if fits(pieces) { return (pieces, droppedTokens) }

        // 3. Trim words from the longest remaining non-date token.
        while !fits(pieces) {
            let candidates = pieces.indices.filter { pieces[$0].kind != .date && pieces[$0].words.count > 1 }
            guard let index = longest(candidates, in: pieces) else { break }
            pieces[index].words.removeLast()
        }
        if fits(pieces) { return (pieces, droppedTokens) }

        // A time is dropped before a date would have to be cut.
        if let index = pieces.firstIndex(where: { $0.kind == .date && $0.timeWord != nil }) {
            pieces[index].timeWord = nil
            if fits(pieces) { return (pieces, droppedTokens) }
        }

        // 4. Cut at a character boundary; a token that cannot shrink further is removed.
        while !fits(pieces) {
            let candidates = pieces.indices.filter { pieces[$0].kind != .date && !pieces[$0].isEmpty }
            guard let index = longest(candidates, in: pieces) else { break }
            guard var word = pieces[index].words.last else { break }
            if word.count <= 1 {
                pieces[index].words.removeLast()
                if pieces[index].words.isEmpty { droppedTokens.append(pieces[index].kind) }
                continue
            }
            word.removeLast()
            word = Sanitizer.trimSeparators(word)
            if word.isEmpty {
                pieces[index].words.removeLast()
            } else {
                pieces[index].words[pieces[index].words.count - 1] = word
            }
        }
        return (pieces, droppedTokens)
    }

    func longest(_ candidates: [Int], in pieces: [Piece]) -> Int? {
        candidates.max { a, b in
            let la = renderPiece(pieces[a]).count
            let lb = renderPiece(pieces[b]).count
            return la == lb ? a < b : la < lb
        }
    }
}

/// The never-include list (3.10). Entries are single words; a word containing a banned
/// word as one of its parts ("ACME-Corp", "ACME's") is removed whole.
public struct NeverInclude: Sendable {
    let keys: Set<String>

    public init(_ words: [String]) {
        keys = Set(words.flatMap { WordTokenizer.words($0) }.flatMap { NeverInclude.parts($0) })
    }

    static func parts(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for character in word {
            if WordTokenizer.isContentCharacter(character) {
                current.append(character)
            } else if !current.isEmpty {
                parts.append(TextFolding.key(current))
                current = ""
            }
        }
        if !current.isEmpty { parts.append(TextFolding.key(current)) }
        return parts
    }

    public func remove(from words: [String]) -> [String] {
        guard !keys.isEmpty else { return words }
        return words.filter { word in !NeverInclude.parts(word).contains(where: keys.contains) }
    }

    public func containsBannedWord(_ text: String) -> Bool {
        guard !keys.isEmpty else { return false }
        return WordTokenizer.words(text, compatibilityNormalize: true).contains { word in
            NeverInclude.parts(word).contains(where: keys.contains)
        }
    }
}
