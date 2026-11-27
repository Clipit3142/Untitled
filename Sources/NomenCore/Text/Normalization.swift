import Foundation

extension String {
    /// True when every byte is ASCII. ASCII text is already in every normalization form,
    /// so the Unicode normalizers below can return it unchanged.
    var isASCIIOnly: Bool { utf8.allSatisfy { $0 < 0x80 } }

    /// Canonical composition (NFC).
    var nfc: String { isASCIIOnly ? self : precomposedStringWithCanonicalMapping }
    /// Compatibility composition (NFKC).
    var nfkc: String { isASCIIOnly ? self : precomposedStringWithCompatibilityMapping }
    /// Canonical decomposition (NFD).
    var nfd: String { isASCIIOnly ? self : decomposedStringWithCanonicalMapping }
}

extension Character {
    /// A decimal digit in any script (0–9, ０–９, ٠–٩ …). Unlike `isNumber`, this excludes
    /// numerals such as "京", "½" and "Ⅻ", which are words or symbols in names.
    var isDecimalDigit: Bool {
        if let ascii = asciiValue { return ascii >= 48 && ascii <= 57 }
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else { return false }
        return scalar.properties.numericType == .decimal
    }
}
