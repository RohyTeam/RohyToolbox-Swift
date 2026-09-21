//
//  ContentView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI
import SwiftData
import LNPopupUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var manager = DownloadManager.shared

    var body: some View {
        TabView {
            ToolboxView()
                .tabItem {
                    Label("Toolbox", systemImage: "wrench.and.screwdriver.fill")
                }
            SwiftStoreView()
                .tabItem {
                    Label("Swift Store", systemImage: "swift")
                }
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle.fill")
                }
                .badge(manager.downloadingCount > 0 ? Text("\(manager.downloadingCount)") : nil)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .task {
            // In unit tests the manager is attached manually with an
            // in-memory container.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            manager.attach(context: modelContext)
        }
        .popup(
            isBarPresented: Binding(
                get: { manager.popupTask != nil },
                set: { if !$0 { manager.popupTaskID = nil } }
            ),
            isPopupOpen: .constant(false)
        ) {
            if let task = manager.popupTask {
                Text(task.fileName)
            }
        }
        .popupBarCustomView(
            wantsDefaultTapGesture: false,
            wantsDefaultPanGesture: false,
            wantsDefaultHighlightGesture: false
        ) {
            if let task = manager.popupTask {
                DownloadPopupBar(task: task)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Counter.self, inMemory: true)
}
