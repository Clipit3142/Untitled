import AppIntents
import Foundation
import UniformTypeIdentifiers
import UntitledCore
import UntitledEngine
import UntitledStore
import UntitledUI

/// Shortcuts actions (3.15, P6): Suggest Name, Rename File, Pause, Resume, and Rename Existing
/// Files in Folder. Files outside granted folders return a clear error.
struct UntitledIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }

    init(_ error: ExplicitError) { message = error.explanation }
    init(message: String) { self.message = message }
}

extension AppController {
    /// The app model once it has loaded, for intents that launch the app in the background.
    @MainActor
    func readyModel() async throws -> AppModel {
        for _ in 0..<100 {
            if let model, model.loaded { return model }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw UntitledIntentError(message: "Untitled is still starting. Try again in a moment.")
    }
}

/// Runs work on a file Shortcuts handed over, inside its security scope.
private func withAccess<T>(to file: IntentFile, _ body: (String) async throws -> T) async throws -> T {
    guard let url = file.fileURL else { throw UntitledIntentError(message: "Choose a file in a folder Untitled can use.") }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try await body(url.path)
}

struct SuggestNameIntent: AppIntent {
    static let title: LocalizedStringResource = "Suggest Name"
    static let description = IntentDescription("Suggests a name for a file in your style. Nothing changes on disk.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "File", supportedContentTypes: [.item])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await AppController.shared.readyModel()
        let name = try await withAccess(to: file) { path in
            do { return try await model.engine.suggestName(path: path) } catch { throw UntitledIntentError(error) }
        }
        return .result(value: name)
    }
}

struct RenameFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Rename File"
    static let description = IntentDescription("Renames a file in your style, and moves it when a rule matches. Undo works as usual.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "File", supportedContentTypes: [.item])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await AppController.shared.readyModel()
        let newPath = try await withAccess(to: file) { path in
            do { return try await model.engine.renameFile(path: path) } catch { throw UntitledIntentError(error) }
        }
        return .result(value: (newPath as NSString).lastPathComponent)
    }
}

enum PauseDuration: String, AppEnum {
    case oneHour, untilTomorrow, indefinitely

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pause Duration")
    static let caseDisplayRepresentations: [PauseDuration: DisplayRepresentation] = [
        .oneHour: "For 1 Hour",
        .untilTomorrow: "Until Tomorrow",
        .indefinitely: "Indefinitely",
    ]

    var option: PauseOption {
        switch self {
        case .oneHour: .oneHour
        case .untilTomorrow: .untilTomorrow
        case .indefinitely: .indefinitely
        }
    }
}

struct PauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Untitled"
    static let description = IntentDescription("Stops renaming new files for a while. “Until tomorrow” resumes at 06:00.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Duration", default: .oneHour)
    var duration: PauseDuration

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppController.shared.readyModel().pause(duration.option)
        return .result()
    }
}

struct ResumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Untitled"
    static let description = IntentDescription("Starts renaming new files again.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AppController.shared.readyModel().resume()
        return .result()
    }
}

/// A watched folder, for "Rename Existing Files in Folder".
struct WatchedFolderEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Folder")
    static let defaultQuery = WatchedFolderQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WatchedFolderQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [WatchedFolderEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WatchedFolderEntity] {
        try await AppController.shared.readyModel().watchedFolders.map { WatchedFolderEntity(id: $0.id, name: $0.displayName) }
    }
}

struct RenameExistingFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Rename Existing Files in Folder"
    static let description = IntentDescription("Proposes names for the files already in a watched folder. They wait in Review.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Folder")
    var folder: WatchedFolderEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let model = try await AppController.shared.readyModel()
        do {
            return .result(value: try await model.engine.renameExisting(folderID: folder.id))
        } catch {
            throw UntitledIntentError(error)
        }
    }
}

struct UntitledShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RenameFileIntent(), phrases: ["Rename a file with \(.applicationName)"],
                    shortTitle: "Rename File", systemImageName: "pencil")
        AppShortcut(intent: SuggestNameIntent(), phrases: ["Suggest a name with \(.applicationName)"],
                    shortTitle: "Suggest Name", systemImageName: "text.cursor")
        AppShortcut(intent: PauseIntent(), phrases: ["Pause \(.applicationName)"],
                    shortTitle: "Pause", systemImageName: "pause.circle")
        AppShortcut(intent: ResumeIntent(), phrases: ["Resume \(.applicationName)"],
                    shortTitle: "Resume", systemImageName: "play.circle")
        AppShortcut(intent: RenameExistingFilesIntent(), phrases: ["Rename existing files in \(\.$folder) with \(.applicationName)"],
                    shortTitle: "Rename Existing Files", systemImageName: "folder.badge.gearshape")
    }
}
