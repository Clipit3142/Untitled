public import Foundation
public import NomenCore
public import NomenFS

/// A folder's role (3.3).
public enum FolderRole: String, Codable, Sendable, Hashable, CaseIterable {
    case watched, destination, accessOnly
}

/// Why a folder needs attention (C2, C5).
public enum FolderAttention: String, Codable, Sendable, Hashable {
    /// Renamed, moved or deleted: offer Reconnect.
    case needsReconnect
    /// Its volume is unmounted.
    case disconnected
}

/// A folder Nomen can write in (3.3).
public struct GrantedFolder: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var displayName: String
    public var bookmark: Data?
    public var role: FolderRole
    public var mode: FolderMode
    public var styleID: String
    public var onlyGenericNames: Bool
    public var genericPatterns: [String]
    public var watchStart: Date
    public var lastEventID: UInt64?
    public var attention: FolderAttention?
    public var offer: AutomaticOfferState
    public var projectConfirmed: Bool
    /// Downloads is granted by entitlement and needs no bookmark (3.3).
    public var isDownloads: Bool

    public init(id: String = UUID().uuidString, path: String, displayName: String? = nil, bookmark: Data? = nil,
                role: FolderRole, mode: FolderMode = .review, styleID: String = Presets.clean.id,
                onlyGenericNames: Bool = true, genericPatterns: [String] = [], watchStart: Date,
                lastEventID: UInt64? = nil, attention: FolderAttention? = nil, offer: AutomaticOfferState = AutomaticOfferState(),
                projectConfirmed: Bool = false, isDownloads: Bool = false) {
        self.id = id
        self.path = path
        self.displayName = displayName ?? FileSystem.name(path)
        self.bookmark = bookmark
        self.role = role
        self.mode = mode
        self.styleID = styleID
        self.onlyGenericNames = onlyGenericNames
        self.genericPatterns = genericPatterns
        self.watchStart = watchStart
        self.lastEventID = lastEventID
        self.attention = attention
        self.offer = offer
        self.projectConfirmed = projectConfirmed
        self.isDownloads = isDownloads
    }

    public var policy: FolderPolicy {
        FolderPolicy(mode: role == .watched ? mode : .off, watchStart: watchStart,
                     onlyGenericNames: onlyGenericNames, userGenericPatterns: genericPatterns)
    }
}

/// A destination for filing rules (3.12).
public struct Destination: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var folderID: String
    public var subfolderPattern: String

    public init(id: String = UUID().uuidString, folderID: String, subfolderPattern: String = "") {
        self.id = id
        self.folderID = folderID
        self.subfolderPattern = subfolderPattern
    }
}

/// An item waiting in the queue: pending generation or ready for Review (3.5).
public struct QueueItem: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable, Hashable {
        /// Waiting to be named (for example, rate limited).
        case pending
        /// Named and waiting for the user in Review.
        case review
    }

    public var id: String
    public var arrival: Int64
    public var folderID: String?
    public var directory: String
    public var expected: ExpectedFile
    public var dateAdded: Date?
    public var status: Status
    public var proposal: Proposal?
    public var burstGroup: String?
    public var request: RequestKind
    public var createdAt: Date

    public init(id: String = UUID().uuidString, arrival: Int64, folderID: String?, directory: String, expected: ExpectedFile,
                dateAdded: Date?, status: Status, proposal: Proposal? = nil, burstGroup: String? = nil,
                request: RequestKind = .automatic, createdAt: Date) {
        self.id = id
        self.arrival = arrival
        self.folderID = folderID
        self.directory = directory
        self.expected = expected
        self.dateAdded = dateAdded
        self.status = status
        self.proposal = proposal
        self.burstGroup = burstGroup
        self.request = request
        self.createdAt = createdAt
    }

    public var path: String { FileSystem.join(directory, expected.name) }
}

/// A line in Activity that is not an operation ("removed from Review because the file is gone").
public struct ActivityNote: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var time: Date
    public var message: String

    public init(id: Int64? = nil, time: Date, message: String) {
        self.id = id
        self.time = time
        self.message = StoredText.clamp(message)
    }
}

/// Stored fields are capped at 200 characters (3.18, E4, W1). Names, paths and bookmarks
/// are exempt.
public enum StoredText {
    public static func clamp(_ text: String) -> String {
        text.count <= Defaults.storedFieldMaxCharacters ? text : String(text.prefix(Defaults.storedFieldMaxCharacters))
    }

    public static func clamp(_ text: String?) -> String? { text.map { clamp($0) } }

    /// A proposal with every free-text field capped.
    public static func clamp(_ proposal: Proposal) -> Proposal {
        var copy = proposal
        copy.fields.source = clamp(copy.fields.source)
        copy.fields.subject = clamp(copy.fields.subject)
        copy.fields.app = clamp(copy.fields.app)
        copy.fields.original = clamp(copy.fields.original)
        copy.parts = copy.parts.map { RenderedPart(token: $0.token, text: clamp($0.text), required: $0.required) }
        copy.subfolder = copy.subfolder.map { clamp($0) }
        return copy
    }
}
