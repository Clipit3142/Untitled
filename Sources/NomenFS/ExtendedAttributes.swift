public import Foundation
import CNomenSys
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Extended attributes, never following symlinks (3.13).
public enum ExtendedAttributes {
    public enum Failure: Error, Equatable {
        case failed(errno: Int32)
    }

    public static func get(_ name: String, atPath path: String) -> Data? {
        let size = nomen_getxattr(path, name, nil, 0)
        guard size >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        let read = buffer.withUnsafeMutableBytes { nomen_getxattr(path, name, $0.baseAddress, Int(size)) }
        guard read >= 0 else { return nil }
        return Data(buffer.prefix(Int(read)))
    }

    public static func set(_ name: String, data: Data, atPath path: String) throws(Failure) {
        let result = data.withUnsafeBytes { nomen_setxattr(path, name, $0.baseAddress, data.count) }
        if result != 0 { throw .failed(errno: errno) }
    }

    public static func remove(_ name: String, atPath path: String) throws(Failure) {
        if nomen_removexattr(path, name) != 0 { throw .failed(errno: errno) }
    }

    /// Attribute names as the platform reports them ("user." prefixes removed on Linux).
    public static func list(atPath path: String) -> [String] {
        let size = nomen_listxattr(path, nil, 0)
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: Int(size))
        let read = buffer.withUnsafeMutableBufferPointer { nomen_listxattr(path, $0.baseAddress, Int(size)) }
        guard read > 0 else { return [] }
        return buffer.prefix(Int(read)).split(separator: 0).map { chars in
            let name = String(decoding: chars.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return name.hasPrefix("user.") ? String(name.dropFirst(5)) : name
        }
    }

    /// Every attribute and its value; used by tests to prove attributes are unchanged (J6, W4).
    public static func all(atPath path: String) -> [String: Data] {
        var result: [String: Data] = [:]
        for name in list(atPath: path) {
            if let value = get(name, atPath: path) { result[name] = value }
        }
        return result
    }
}

/// The marker Nomen sets on every file it renamed (3.3, 3.13): a binary plist with the
/// original name, the state and the first-renamed date. A marked file is never processed
/// automatically again, in any state.
public struct Marker: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable {
        case renamed, restored
    }

    public var originalName: String
    public var state: State
    public var firstRenamed: Date

    public init(originalName: String, state: State, firstRenamed: Date) {
        self.originalName = originalName
        self.state = state
        self.firstRenamed = firstRenamed
    }

    public static let attributeName = "com.yourcompany.Nomen.original"

    public static func read(atPath path: String) -> Marker? {
        guard let data = ExtendedAttributes.get(attributeName, atPath: path) else { return nil }
        return try? PropertyListDecoder().decode(Marker.self, from: data)
    }

    public func write(toPath path: String) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(self)
        try ExtendedAttributes.set(Marker.attributeName, data: data, atPath: path)
    }

    /// The attribute names Nomen owns; every other attribute must stay byte-identical.
    public static let ownedAttributes: Set<String> = [attributeName]
}
