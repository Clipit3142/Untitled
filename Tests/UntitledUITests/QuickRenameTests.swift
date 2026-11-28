import Foundation
import Testing
@testable import UntitledUI
import UntitledCore
import UntitledEngine
import UntitledFS
import UntitledStore

@Suite("Quick Rename (M5, M6, H9)", .serialized)
@MainActor
struct QuickRenameTests {
    @Test("Return applies the proposal; Esc changes nothing")
    func applyAndCancel() async throws {
        let harness = try await ModelHarness(mode: .off)
        await harness.model.updateOnboarding { $0.skip() }
        let path = harness.scan()
        let router = AppRouter()

        let cancelled = QuickRenameModel(paths: [path], app: harness.model, router: router)
        await cancelled.load()
        #expect(cancelled.phase == .ready)
        let entry = try #require(cancelled.entries.first)
        #expect(!entry.baseName.isEmpty)
        #expect(entry.fileExtension == "pdf")
        // Esc: the model is dropped without applying.
        #expect(harness.desktopNames == [ModelHarness.scanName])

        let quick = QuickRenameModel(paths: [path], app: harness.model, router: router)
        await quick.load()
        #expect(await quick.apply())
        #expect(quick.phase == .finished)
        let renamed = try #require(quick.entries.first?.renamedPath)
        #expect(FileSystem.name(renamed) == entry.baseName + ".pdf")
        #expect(harness.desktopNames == [entry.baseName + ".pdf"])
        await harness.finish()
    }

    @Test("Typed names are used as typed, with any sanitizer change shown first (H9)")
    func typedName() async throws {
        let harness = try await ModelHarness(mode: .off)
        await harness.model.updateOnboarding { $0.skip() }
        let path = harness.scan()
        let quick = QuickRenameModel(paths: [path], app: harness.model, router: AppRouter())
        await quick.load()
        quick.setBaseName("my INVOICE: final", for: path)
        #expect(quick.typedNotice(for: path)?.contains("my INVOICE") == true)
        quick.setBaseName("my INVOICE final", for: path)
        #expect(quick.typedNotice(for: path) == nil)
        #expect(await quick.apply())
        #expect(harness.desktopNames == ["my INVOICE final.pdf"])
        await harness.finish()
    }

    @Test("Outside granted folders: declining access leaves the file untouched and offers Copy name (M6)")
    func declineAccess() async throws {
        let harness = try await ModelHarness(mode: .off)
        await harness.model.updateOnboarding { $0.skip() }
        let elsewhere = FileSystem.join(harness.root, "Elsewhere")
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        let path = harness.scan(); let moved = FileSystem.join(elsewhere, ModelHarness.scanName)
        try FileManager.default.moveItem(atPath: path, toPath: moved)

        let router = AppRouter()
        var askedFor: URL?
        var copied: String?
        router.chooseFolder = { url, _ in askedFor = url; return nil }
        router.copyToPasteboard = { copied = $0 }
        let quick = QuickRenameModel(paths: [moved], app: harness.model, router: router)
        await quick.load()
        #expect(quick.phase == .needsAccess(folder: elsewhere))
        await quick.requestAccess()
        #expect(askedFor?.path == elsewhere)
        #expect(quick.phase == .copyOnly)
        #expect(await quick.apply() == false)
        quick.copyNames()
        #expect(copied?.hasSuffix(".pdf") == true)
        #expect(FileManager.default.fileExists(atPath: moved))
        await harness.finish()
    }

    @Test("Granting the folder in the picker lets the rename go ahead (M6)")
    func grantAccess() async throws {
        let harness = try await ModelHarness(mode: .off)
        await harness.model.updateOnboarding { $0.skip() }
        let elsewhere = FileSystem.join(harness.root, "Elsewhere")
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        let moved = FileSystem.join(elsewhere, ModelHarness.scanName)
        try FileManager.default.moveItem(atPath: harness.scan(), toPath: moved)
        let router = AppRouter()
        router.chooseFolder = { url, _ in url.map { FolderChoice(url: $0, bookmark: nil) } }
        let quick = QuickRenameModel(paths: [moved], app: harness.model, router: router)
        await quick.load()
        await quick.requestAccess()
        #expect(quick.phase == .ready)
        #expect(harness.model.folders.contains { $0.path == elsewhere && $0.role == .accessOnly })
        #expect(await quick.apply())
        #expect(!FileManager.default.fileExists(atPath: moved))
        await harness.finish()
    }

    @Test("Selections outside 1–50 files are refused with a reason")
    func selectionSize() async throws {
        let harness = try await ModelHarness(mode: .off)
        let quick = QuickRenameModel(paths: [], app: harness.model, router: AppRouter())
        await quick.load()
        #expect(quick.phase == .failed("Select between 1 and 50 files (you selected 0)."))
        await harness.finish()
    }
}
