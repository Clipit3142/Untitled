public import Foundation

/// Coordinates a move so documents open in other apps follow it (3.13 step 2, J5).
public protocol FileCoordinating: Sendable {
    func coordinateMove(from source: URL, to destination: URL, _ body: () throws -> Void) throws
}

/// No coordination (Linux tests).
public struct DirectMove: FileCoordinating {
    public init() {}
    public func coordinateMove(from source: URL, to destination: URL, _ body: () throws -> Void) throws {
        try body()
    }
}

#if canImport(Darwin) && !os(Linux)
/// NSFileCoordinator with the moving options, so Preview, TextEdit and Pages keep editing
/// the renamed file.
public struct CoordinatedMove: FileCoordinating {
    public init() {}

    public func coordinateMove(from source: URL, to destination: URL, _ body: () throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var bodyError: (any Error)?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { newSource, newDestination in
            coordinator.item(at: newSource, willMoveTo: newDestination)
            do {
                try body()
                coordinator.item(at: newSource, didMoveTo: newDestination)
            } catch {
                bodyError = error
            }
        }
        if let bodyError { throw bodyError }
        if let coordinationError { throw coordinationError }
    }
}
#endif
