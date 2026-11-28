public import Foundation
import UntitledFS

/// What the app and the Finder extension share through the app-group container (3.15).
public enum SharedHandoff {
    /// The app group, prefixed with the team identifier as macOS requires.
    public static let appGroupSuffix = "com.yourcompany.Untitled"

    public static func containerURL(groupIdentifier: String) -> URL? {
        #if os(macOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        #else
        nil
        #endif
    }

    /// A Finder request. The `untitled://` URL carries only its ID (P5).
    public struct Request: Codable, Sendable, Hashable {
        public enum Action: String, Codable, Sendable {
            case rename
            case restoreOriginalName
        }

        public var id: UUID
        public var action: Action
        public var paths: [String]
        public var created: Date

        public init(id: UUID = UUID(), action: Action, paths: [String], created: Date = Date()) {
            self.id = id
            self.action = action
            self.paths = paths
            self.created = created
        }

        public var url: URL { URL(string: "untitled://request/\(id.uuidString)")! }
    }

    static func requestsDirectory(in container: URL) -> URL {
        container.appendingPathComponent("Requests", isDirectory: true)
    }

    /// Writes a request for the app to pick up.
    public static func write(_ request: Request, container: URL) throws {
        let directory = requestsDirectory(in: container)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(request).write(to: directory.appendingPathComponent(request.id.uuidString + ".json"), options: .atomic)
    }

    /// Reads and removes the request a URL names. Malformed, unknown or stale IDs yield nil (P5).
    public static func take(url: URL, container: URL, now: Date = Date()) -> Request? {
        guard url.scheme == "untitled", url.host == "request", url.pathComponents.count == 2,
              let id = UUID(uuidString: url.pathComponents[1]) else { return nil }
        let file = requestsDirectory(in: container).appendingPathComponent(id.uuidString + ".json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.removeItem(at: file)
        guard let request = try? JSONDecoder().decode(Request.self, from: data), request.id == id,
              now.timeIntervalSince(request.created) < 300,
              (1...50).contains(request.paths.count) else { return nil }
        return request
    }

    /// The granted folders, published by the app so the Finder extension shows its items only there.
    public static func publishGrantedFolders(_ paths: [String], container: URL) {
        let file = container.appendingPathComponent("GrantedFolders.json")
        try? JSONEncoder().encode(paths).write(to: file, options: .atomic)
    }

    public static func grantedFolders(container: URL) -> [String] {
        let file = container.appendingPathComponent("GrantedFolders.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// True when Untitled renamed this file and it has not been restored ("Restore Original Name").
    public static func canRestore(path: String) -> Bool {
        Marker.read(atPath: path)?.state == .renamed
    }
}
