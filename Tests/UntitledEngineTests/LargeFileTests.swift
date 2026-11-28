import Foundation
import Testing
@testable import UntitledEngine
import UntitledFS

/// D1: a 2 GB file written over 60 s is processed exactly once, and only after the write
/// finishes. Runs when UNTITLED_SLOW_TESTS=1 (about 70 s and 2 GB of disk).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UNTITLED_SLOW_TESTS"] == "1"))
struct LargeFileTests {
    @Test(.timeLimit(.minutes(5)))
    func largeSlowWriteIsProcessedOnceAfterItFinishes() async throws {
        let h = try await EngineHarness(mode: .review, productionTiming: true)
        let path = FileSystem.join(h.desktop, "download.pdf")
        let header = Data((EngineHarness.invoice + "\n").utf8)
        _ = FileManager.default.createFile(atPath: path, contents: header)
        let handle = try #require(FileHandle(forWritingAtPath: path))
        let chunk = Data(repeating: 0x20, count: 32 * 1_024 * 1_024)
        let total: Int64 = 2 * 1_024 * 1_024 * 1_024
        let clock = ContinuousClock()
        let start = clock.now
        var written: Int64 = 0
        while written < total {
            handle.seekToEndOfFile()
            handle.write(chunk)
            written += Int64(chunk.count)
            // 64 chunks over 60 s.
            try await Task.sleep(until: start + .milliseconds(Int(Double(written) / Double(total) * 60_000)), clock: clock)
            #expect(await h.engine.queue().isEmpty, "nothing is processed while the file is being written")
        }
        try handle.close()
        let finished = clock.now
        #expect(finished - start >= .seconds(59))
        #expect(await eventually(.seconds(30)) { await h.engine.reviewItems().count == 1 })
        try await Task.sleep(for: .seconds(2))
        #expect(await h.engine.queue().count == 1, "processed exactly once")
        // Over the 200 MB content-reading limit: a metadata-only proposal, never read by the model.
        #expect(h.model.calls.isEmpty)
        let proposal = try #require(await h.engine.reviewItems().first?.proposal)
        #expect(proposal.lowReasons.contains(.metadataOnly))
        await h.stop()
        try? FileManager.default.removeItem(atPath: path)
    }
}
