public import Foundation

/// Every default and limit from spec 3.4, in one place. Other code reads these values
/// instead of repeating literals, so a spike result changes one line here (and the spec).
public enum Defaults {
    // Stability gate
    public static let stabilityWait: TimeInterval = 1.0
    public static let stabilityWaitRange: ClosedRange<TimeInterval> = 0.5...10
    public static let stabilityCheckInterval: TimeInterval = 0.5

    // Extraction
    public static let pdfPagesRead = 2
    public static let pdfPagesRange: ClosedRange<Int> = 1...5
    public static let contentTokenBudget = 3_000
    public static let contextReserveTokens = 1_000
    public static let ocrMaxPixels = 4_096
    public static let modelImageMaxPixels = 1_536
    public static let quickLookThumbnailPixels = 1_024
    public static let scanPageCharacterThreshold = 30
    public static let scanRenderDPI: Double = 200
    public static let contentReadingSizeLimit: Int64 = 200 * 1_024 * 1_024

    // Naming
    public static let maxNameLength = 60
    public static let maxNameLengthRange: ClosedRange<Int> = 20...150
    public static let subjectWords = 5
    public static let subjectWordsRange: ClosedRange<Int> = 1...12
    public static let sourceMaxWords = 4
    public static let maxFileNameBytes = 255
    public static let collisionRange: ClosedRange<Int> = 2...99
    public static let piiDigitRun = 9

    // Learning
    public static let examplesStored = 20
    public static let examplesUsed = 5
    public static let learningThreshold = 2
    public static let learningWindow: TimeInterval = 30 * 24 * 3_600
    public static let finderEditWindow: TimeInterval = 7 * 24 * 3_600
    public static let learnFromFolderMinimum = 10
    public static let exampleNamesRange: ClosedRange<Int> = 3...5

    // Bursts and notifications
    public static let burstThreshold = 10
    public static let burstWindow: TimeInterval = 30
    public static let notificationBatchThreshold = 4
    public static let notificationBatchWindow: TimeInterval = 10

    // Model
    public static let generationTimeout: TimeInterval = 20
    public static let rateLimitBackoff: [TimeInterval] = [5, 15, 60]
    public static let rateLimitRepeatInterval: TimeInterval = 300
    public static let promptExamples = 5
    public static let contentLineLimit = 40

    // History, caches, pauses
    public static let historyRetentionDays = 90
    public static let historyRetentionChoices: [Int?] = [30, 90, 365, nil]
    public static let thumbnailCacheBytes: Int64 = 200 * 1_024 * 1_024
    public static let pauseResumeHour = 6
    public static let ownOperationSuppression: TimeInterval = 5
    public static let resumeAfterConditionClears: TimeInterval = 10

    // Explicit requests
    public static let quickRenameSelection: ClosedRange<Int> = 1...50

    // "Go Automatic?" offer
    public static let automaticOfferAccepted = 20
    public static let automaticOfferMaxEdits = 2

    // Storage
    public static let storedFieldMaxCharacters = 200

    // App timeline for screenshot app detection
    public static let appTimelineWindow: TimeInterval = 10 * 60
}
