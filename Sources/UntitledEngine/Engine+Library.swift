import Foundation
public import UntitledCore
import UntitledFS
public import UntitledStore

extension Engine {
    // MARK: Styles

    /// Saved styles first, then the presets that have not been saved over.
    public func styles() -> [NamingStyle] {
        let saved = (try? deps.config.styles()) ?? []
        let savedIDs = Set(saved.map(\.id))
        return saved + Presets.all.filter { !savedIDs.contains($0.id) }
    }

    /// Deletes a custom style. Folders using it switch to Clean.
    public func deleteStyle(id: String) throws {
        guard !Presets.all.contains(where: { $0.id == id }) else { return }
        try deps.config.deleteStyle(id: id)
        for var folder in folders.values where folder.styleID == id {
            folder.styleID = Presets.clean.id
            try updateFolder(folder)
        }
        emit(.libraryChanged)
    }

    // MARK: Rules and destinations (3.12)

    public func rules() -> [Rule] { (try? deps.config.rules()) ?? [] }

    /// Saves the ordered rule list; queued proposals pick up the new filing on their next re-format.
    public func saveRules(_ rules: [Rule]) throws {
        try deps.config.saveRules(rules)
        emit(.libraryChanged)
    }

    public func destinations() -> [Destination] { (try? deps.config.destinations()) ?? [] }

    public func saveDestination(_ destination: Destination) throws {
        try deps.config.save(destination)
        emit(.libraryChanged)
    }

    public func customKinds() -> [CustomKind] { (try? deps.config.customKinds()) ?? [] }

    /// Custom kinds apply from the next file (F7).
    public func saveCustomKinds(_ kinds: [CustomKind]) throws {
        try deps.config.saveCustomKinds(kinds)
        emit(.libraryChanged)
    }

    // MARK: Examples (I4)

    public func examples(styleID: String) -> ExampleList {
        (try? deps.config.examples(styleID: styleID)) ?? ExampleList()
    }

    public func saveExamples(_ examples: ExampleList, styleID: String) throws {
        try deps.config.saveExamples(examples, styleID: styleID)
        emit(.libraryChanged)
    }

    // MARK: App settings

    /// Settings the app owns (Dock, sounds, onboarding), stored with the configuration so Reset clears them.
    public func appSetting<T: Decodable & Sendable>(_ type: T.Type, key: String) -> T? {
        try? deps.config.setting(type, key: "app." + key)
    }

    public func setAppSetting<T: Encodable & Sendable>(_ value: T, key: String) {
        try? deps.config.setSetting(value, key: "app." + key)
    }

    // MARK: Learning a style (3.10, B5)

    /// Reads the names in a folder once (no lasting access) and infers a style from them.
    public func learnStyle(fromFolder path: String) throws(StyleInferenceError) -> InferredStyle {
        let names = ((try? FileSystem.entries(ofDirectory: path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .filter { FileSystem.status(atPath: FileSystem.join(path, $0))?.isRegularFile == true }
            .map { FileExtension.split($0).base }
        return try StyleInference.inferFromFolder(names)
    }

    /// The fields of queued proposals, for the live style preview (it never calls the model).
    public func previewSamples(limit: Int = 4) -> [StylePreviewSample] {
        queue().compactMap { item in
            item.proposal.map {
                StylePreviewSample(fields: $0.fields, fileExtension: FileExtension.split(item.expected.name).extension,
                                   isScreenshot: $0.isScreenshot, language: $0.language)
            }
        }.prefix(limit).map { $0 }
    }
}

/// A sample file in the style preview: stored fields only (3.15 Styles).
public struct StylePreviewSample: Sendable, Hashable {
    public var fields: NameFields
    public var fileExtension: String?
    public var isScreenshot: Bool
    public var language: NameLanguage

    public init(fields: NameFields, fileExtension: String?, isScreenshot: Bool, language: NameLanguage = .english) {
        self.fields = fields
        self.fileExtension = fileExtension
        self.isScreenshot = isScreenshot
        self.language = language
    }
}
