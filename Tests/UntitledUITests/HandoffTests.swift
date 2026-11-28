import Foundation
import Testing
import UntitledShared
import UntitledFS

@Suite("Finder handoff (P4, P5)")
struct HandoffTests {
    let container: URL

    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("untitled-group-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    @Test("A written request is taken exactly once")
    func roundTrip() throws {
        let request = SharedHandoff.Request(action: .rename, paths: ["/Users/a/Desktop/Screenshot.png"])
        try SharedHandoff.write(request, container: container)
        #expect(request.url.absoluteString == "untitled://request/\(request.id.uuidString)")
        let taken = SharedHandoff.take(url: request.url, container: container)
        #expect(taken == request)
        #expect(SharedHandoff.take(url: request.url, container: container) == nil)
    }

    @Test("Forged, unknown, malformed or stale IDs do nothing")
    func forged() throws {
        let unknown = URL(string: "untitled://request/\(UUID().uuidString)")!
        #expect(SharedHandoff.take(url: unknown, container: container) == nil)
        for text in ["untitled://request/not-a-uuid", "untitled://request/../../etc/passwd", "untitled://other/\(UUID().uuidString)",
                     "https://request/\(UUID().uuidString)", "untitled://request/\(UUID().uuidString)/extra", "untitled://request"] {
            #expect(SharedHandoff.take(url: URL(string: text)!, container: container) == nil, "\(text)")
        }
        // A request file whose content names another ID is refused.
        let real = SharedHandoff.Request(action: .rename, paths: ["/a"])
        let forgedID = UUID()
        try SharedHandoff.write(real, container: container)
        try FileManager.default.moveItem(at: container.appendingPathComponent("Requests/\(real.id.uuidString).json"),
                                         to: container.appendingPathComponent("Requests/\(forgedID.uuidString).json"))
        #expect(SharedHandoff.take(url: URL(string: "untitled://request/\(forgedID.uuidString)")!, container: container) == nil)
        // Stale requests (older than 5 minutes) are refused.
        let stale = SharedHandoff.Request(action: .rename, paths: ["/a"], created: Date().addingTimeInterval(-600))
        try SharedHandoff.write(stale, container: container)
        #expect(SharedHandoff.take(url: stale.url, container: container) == nil)
        // Selections outside 1–50 files are refused.
        let tooMany = SharedHandoff.Request(action: .rename, paths: (0..<51).map { "/a/\($0)" })
        try SharedHandoff.write(tooMany, container: container)
        #expect(SharedHandoff.take(url: tooMany.url, container: container) == nil)
        let none = SharedHandoff.Request(action: .rename, paths: [])
        try SharedHandoff.write(none, container: container)
        #expect(SharedHandoff.take(url: none.url, container: container) == nil)
        // Garbage in the file is refused.
        let garbageID = UUID()
        try Data("{".utf8).write(to: container.appendingPathComponent("Requests/\(garbageID.uuidString).json"))
        #expect(SharedHandoff.take(url: URL(string: "untitled://request/\(garbageID.uuidString)")!, container: container) == nil)
    }

    @Test("Granted folders are shared with the extension")
    func grantedFolders() {
        #expect(SharedHandoff.grantedFolders(container: container).isEmpty)
        SharedHandoff.publishGrantedFolders(["/Users/a/Desktop", "/Users/a/Downloads"], container: container)
        #expect(SharedHandoff.grantedFolders(container: container) == ["/Users/a/Desktop", "/Users/a/Downloads"])
    }

    @Test("Restore Original Name shows only when the marker says renamed")
    func restore() throws {
        let file = container.appendingPathComponent("Invoice.pdf").path
        _ = FileManager.default.createFile(atPath: file, contents: Data("x".utf8))
        #expect(!SharedHandoff.canRestore(path: file))
        try Marker(originalName: "Scan.pdf", state: .renamed, firstRenamed: Date()).write(toPath: file)
        #expect(SharedHandoff.canRestore(path: file))
        try Marker(originalName: "Scan.pdf", state: .restored, firstRenamed: Date()).write(toPath: file)
        #expect(!SharedHandoff.canRestore(path: file))
    }
}
