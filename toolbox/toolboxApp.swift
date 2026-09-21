//
//  toolboxApp.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI
import SwiftData

@main
struct toolboxApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            // UI tests start with a clean browser state.
            UserDefaults.standard.removeObject(forKey: "webDownloadLastURL")
        }
        UserDefaults.standard.register(defaults: [
            "downloadSegmentCount": 4,
            "maxConcurrentDownloads": 4,
        ])

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appending(path: "Downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Counter.self,
            DownloadRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // The persisted store uses an older schema that SwiftData cannot
            // migrate; discard it and start with a clean store.
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
