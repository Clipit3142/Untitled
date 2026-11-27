import Foundation

/// Reads macOS default screenshot names in any language (3.7, third detection signal).
public enum ScreenshotName {
    public struct Match: Sendable, Hashable {
        public var isRecording: Bool
        public var captureDate: DateValue?
    }

    /// Returns a match when the name looks like a system screenshot or screen-recording name.
    /// The capture time is read from the name when it carries one.
    public static func parse(_ fileName: String) -> Match? {
        let base = FileExtension.split(fileName).base.precomposedStringWithCompatibilityMapping
        let lowered = base.lowercased()
        let runs = GenericNameDetector.letterRuns(lowered).map(TextFolding.key)
        let hasScreenshotWord = runs.contains { GenericWords.screenshot.contains($0) }
            && !runs.allSatisfy({ ["d", "l"].contains($0) })
        let hasRecordingWord = runs.contains { GenericWords.recording.contains($0) }
        let android = lowered.hasPrefix("screenshot_") || lowered.hasPrefix("screen_recording_")
        guard hasScreenshotWord || hasRecordingWord || android else { return nil }
        // Other words must be connectors or time markers; otherwise the user named it.
        guard GenericNameDetector.remainingLetterWeight(lowered) < 3 || android else { return nil }
        let isRecording = hasRecordingWord && !runs.contains("screenshot")
        return Match(isRecording: isRecording, captureDate: captureDate(in: lowered))
    }

    /// Finds "YYYY-MM-DD … H.MM.SS" (with an optional AM/PM marker) or Android's
    /// "YYYYMMDD-HHMMSS". Thai Buddhist years (2400+) are converted.
    static func captureDate(in lowered: String) -> DateValue? {
        let scalars = Array(lowered.unicodeScalars)
        let digitsAndSeparators = scalars.map { s -> Character in
            if (48...57).contains(s.value) { return Character(s) }
            return " "
        }
        let groups = String(digitsAndSeparators).split(separator: " ").map(String.init)
        // Android compact: 20261127 140512
        if let first = groups.first, first.count == 8, let year = Int(first.prefix(4)),
           let month = Int(first.dropFirst(4).prefix(2)), let day = Int(first.suffix(2)) {
            var hour: Int?, minute: Int?
            if groups.count >= 2, groups[1].count >= 4 {
                hour = Int(groups[1].prefix(2)); minute = Int(groups[1].dropFirst(2).prefix(2))
            }
            return DateValue(year: normalizeYear(year), month: month, day: day, hour: hour, minute: minute)
                ?? DateValue(year: normalizeYear(year), month: month, day: day)
        }
        // Dashed: 2026 11 27 14 05 12 (separators already blanked)
        guard groups.count >= 3, groups[0].count == 4, let year = Int(groups[0]),
              let month = Int(groups[1]), let day = Int(groups[2]) else { return nil }
        var hour: Int?
        var minute: Int?
        if groups.count >= 5, let h = Int(groups[3]), let m = Int(groups[4]) {
            hour = h
            minute = m
            if let h = hour, isPM(lowered), h < 12 { hour = h + 12 }
            if let h = hour, isAM(lowered), h == 12 { hour = 0 }
        }
        return DateValue(year: normalizeYear(year), month: month, day: day, hour: hour, minute: minute)
            ?? DateValue(year: normalizeYear(year), month: month, day: day)
    }

    private static func normalizeYear(_ year: Int) -> Int {
        year > 2400 ? year - 543 : year
    }

    private static let pmMarkers = [" pm", "p.m", "下午", "午後", "오후", "μ.μ", "μμ", " م", "pm"]
    private static let amMarkers = [" am", "a.m", "上午", "午前", "오전", "π.μ", "πμ", " ص"]

    private static func isPM(_ lowered: String) -> Bool { pmMarkers.contains { lowered.contains($0) } }
    private static func isAM(_ lowered: String) -> Bool { amMarkers.contains { lowered.contains($0) } }
}
