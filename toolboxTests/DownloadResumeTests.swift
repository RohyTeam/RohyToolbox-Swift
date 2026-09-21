//
//  DownloadResumeTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import SwiftData
import Testing
@testable import toolbox

/// Integration test against scripts/range_server.py (must be running):
/// verifies that pausing a segmented download caches what was already
/// downloaded and that resume produces a byte-identical file.
@MainActor
struct DownloadResumeTests {
    private struct TimeoutError: Error, CustomStringConvertible {
        let stage: String
        let diagnostics: String
        var description: String { "Timed out at: \(stage) | \(diagnostics)" }
    }

    @Test func pauseResumeProducesIdenticalFile() async throws {
        let container = try ModelContainer(
            for: DownloadRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let manager = DownloadManager()
        manager.attach(context: container.mainContext)

        manager.add(url: URL(string: "http://127.0.0.1:18743/test.bin")!)
        let task = try #require(manager.tasks.first)

        try await waitUntil("initial download", task: task) {
            task.state == .downloading && task.downloadedBytes > 0
        }

        manager.pause(task)
        #expect(task.state == .paused)
        let pausedBytes = task.downloadedBytes
        #expect(pausedBytes > 0)

        // Give the resume-data callbacks a moment to land on disk.
        try await Task.sleep(for: .seconds(1))

        manager.resume(task)
        try await waitUntil("resumed download", task: task) { task.state == .downloading }
        // Downloaded bytes were cached, not restarted from zero.
        #expect(task.downloadedBytes >= pausedBytes)

        try await waitUntil("completion", task: task) { task.state == .completed }

        let sourceFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/test.bin")
        let expected = try Data(contentsOf: sourceFile)
        let destination = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads/test.bin")
        let actual = try Data(contentsOf: destination)
        #expect(actual == expected)

        manager.delete(task, removeFile: true)
    }

    /// Real-world case: GitHub release URLs redirect to S3-presigned URLs,
    /// which reject HEAD — the probe must still detect range support.
    @Test func gitHubReleaseDownloadIsSegmented() async throws {
        let container = try ModelContainer(
            for: DownloadRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let manager = DownloadManager()
        manager.attach(context: container.mainContext)

        manager.add(url: URL(
            string: "https://github.com/DeeChael/lanlu-iOS/releases/download/v1.0.0/lanlu-iOS.ipa"
        )!)
        let task = try #require(manager.tasks.first)

        try await waitUntil("probe", task: task) { task.isSegmented || task.state == .failed }
        #expect(task.supportsRange)
        #expect(task.isSegmented)
        #expect(task.totalBytes != nil)

        manager.delete(task, removeFile: true)
    }

    private func waitUntil(
        _ stage: String,
        timeout: Duration = .seconds(30),
        task: DownloadTask,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw TimeoutError(
            stage: stage,
            diagnostics: "state=\(task.state) bytes=\(task.downloadedBytes) "
                + "total=\(String(describing: task.totalBytes)) range=\(task.supportsRange) "
                + "segments=\(task.segmentBytes) err=\(task.errorMessage ?? "-")"
        )
    }
}
