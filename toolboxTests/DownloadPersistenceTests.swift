//
//  DownloadPersistenceTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import SwiftData
import Testing
@testable import toolbox

/// Verifies that multiple download records coexist and that records
/// (including custom headers) survive a container recreation, i.e. an
/// app relaunch.
@MainActor
struct DownloadPersistenceTests {

    private func makeStoreURL() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("test.store"))
    }

    @Test func recordsPersistAcrossContainers() async throws {
        let (directory, storeURL) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: storeURL)

        let first = try ModelContainer(for: DownloadRecord.self, configurations: configuration)
        let context = first.mainContext
        context.insert(DownloadRecord(
            urlString: "http://127.0.0.1:19999/a.bin",
            fileName: "a.bin",
            headers: ["Cookie": "session=abc"],
            requestedSegments: 4
        ))
        context.insert(DownloadRecord(
            urlString: "http://127.0.0.1:19999/b.bin",
            fileName: "b.bin",
            requestedSegments: 4
        ))
        try context.save()

        let second = try ModelContainer(for: DownloadRecord.self, configurations: configuration)
        let records = try second.mainContext.fetch(FetchDescriptor<DownloadRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.fileName == "a.bin" }?.headers["Cookie"] == "session=abc")
    }

    @Test func addingMultipleTasksKeepsAllOfThem() async throws {
        let container = try ModelContainer(
            for: DownloadRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let manager = DownloadManager()
        manager.attach(context: container.mainContext)

        // Unreachable port: tasks are created but never start downloading.
        manager.add(url: URL(string: "http://127.0.0.1:19999/a.bin")!)
        manager.add(url: URL(string: "http://127.0.0.1:19999/b.bin")!)

        #expect(manager.tasks.count == 2)
        let records = try container.mainContext.fetch(FetchDescriptor<DownloadRecord>())
        #expect(records.count == 2)

        // Stop in-flight work before the container goes away.
        for task in manager.tasks {
            manager.delete(task, removeFile: false)
        }
    }

    /// Simulates: add a download, quit the app, relaunch, add another one.
    /// Both records must still be there.
    @Test func recordsSurviveRelaunchAndNewAdds() async throws {
        let (directory, storeURL) = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: storeURL)

        let first = try ModelContainer(for: DownloadRecord.self, configurations: configuration)
        let firstManager = DownloadManager()
        firstManager.attach(context: first.mainContext)
        firstManager.add(url: URL(string: "http://127.0.0.1:19999/a.bin")!)
        #expect(firstManager.tasks.count == 1)

        // Relaunch with a fresh container over the same store.
        let second = try ModelContainer(for: DownloadRecord.self, configurations: configuration)
        let manager = DownloadManager()
        manager.attach(context: second.mainContext)
        #expect(manager.tasks.count == 1)

        manager.add(url: URL(string: "http://127.0.0.1:19999/b.bin")!)
        #expect(manager.tasks.count == 2)
        let records = try second.mainContext.fetch(FetchDescriptor<DownloadRecord>())
        #expect(records.count == 2)

        // Stop in-flight work before the containers go away.
        for task in firstManager.tasks {
            firstManager.delete(task, removeFile: false)
        }
        for task in manager.tasks {
            manager.delete(task, removeFile: false)
        }
    }
}
