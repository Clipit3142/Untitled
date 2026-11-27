/// A deterministic random generator (SplitMix64), so property tests are reproducible and
/// a failure can be replayed from its seed.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SeededGenerator {
    /// A random Unicode scalar, biased towards the troublesome ones.
    mutating func troublesomeScalar() -> Unicode.Scalar {
        let pools: [ClosedRange<UInt32>] = [
            0x00...0x1F, 0x20...0x7E, 0x7F...0x9F, 0xA0...0x2FF, 0x300...0x36F, 0x370...0x52F,
            0x590...0x6FF, 0x900...0x97F, 0xE00...0xE7F, 0x1100...0x11FF, 0x180E...0x180E,
            0x2000...0x206F, 0x2190...0x21FF, 0x2600...0x27BF, 0x3000...0x30FF, 0x4E00...0x4FFF,
            0xAC00...0xACFF, 0xD7B0...0xD7FF, 0xE000...0xE0FF, 0xFB00...0xFB4F, 0xFE00...0xFE0F,
            0xFEFF...0xFEFF, 0xFF00...0xFFEF, 0xFFF0...0xFFFF, 0x1F000...0x1F6FF, 0x1F900...0x1F9FF,
            0xE0000...0xE007F, 0xF0000...0xF00FF, 0x10FFF0...0x10FFFF,
        ]
        let special: [UInt32] = [0x2F, 0x3A, 0x00, 0x5C, 0x2A, 0x3F, 0x22, 0x3C, 0x3E, 0x7C, 0x2E, 0x20,
                                 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D,
                                 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x061C, 0x00AD, 0xFEFF, 0x2028,
                                 0x2029, 0x0085, 0x00A0, 0x3000, 0x2800, 0x3164, 0xFE0F, 0x20E3, 0x1F1E8,
                                 0x2013, 0x5F, 0x2D]
        while true {
            let value: UInt32
            if Int.random(in: 0..<4, using: &self) == 0 {
                value = special.randomElement(using: &self)!
            } else {
                let pool = pools.randomElement(using: &self)!
                value = UInt32.random(in: pool, using: &self)
            }
            if let scalar = Unicode.Scalar(value) { return scalar }
        }
    }

    mutating func troublesomeString(maxLength: Int) -> String {
        let length = Int.random(in: 0...maxLength, using: &self)
        var scalars = String.UnicodeScalarView()
        for _ in 0..<length { scalars.append(troublesomeScalar()) }
        return String(scalars)
    }

    mutating func word() -> String {
        let words = ["invoice", "Swisscom", "mobile", "subscription", "November", "réservation", "Straße",
                     "iPhone", "eBay", "PDF", "Q3", "2026", "covid-19", "l'offre", "don't", "東京", "請求書",
                     "청구서", "отчёт", "📄", "🎉", "R&D", "v1.2", "the", "of", "and", "ACME", "x", "A",
                     "naïve", "Zürich", "São", "Paulo", "e-mail", "WiFi", "5G", "1234", "12345678"]
        return words.randomElement(using: &self)!
    }

    mutating func phrase(maxWords: Int) -> String {
        let count = Int.random(in: 0...maxWords, using: &self)
        return (0..<count).map { _ in word() }.joined(separator: " ")
    }
}
