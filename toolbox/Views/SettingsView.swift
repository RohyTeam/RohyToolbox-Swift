//
//  SettingsView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("swiftStoreLatestBeta") private var swiftStoreLatestBeta = false
    @AppStorage("downloadSegmentCount") private var downloadSegmentCount = 4
    @AppStorage("maxConcurrentDownloads") private var maxConcurrentDownloads = 4

    var body: some View {
        NavigationStack {
            Form {
                Section("Swift Store") {
                    Toggle("Latest Beta", isOn: $swiftStoreLatestBeta)
                }
                Section("Downloads") {
                    Picker("Segment Count", selection: $downloadSegmentCount) {
                        ForEach(1...16, id: \.self) { count in
                            Text(count, format: .number).tag(count)
                        }
                    }
                    Picker("Max Concurrent Tasks", selection: $maxConcurrentDownloads) {
                        ForEach(1...10, id: \.self) { count in
                            Text(count, format: .number).tag(count)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
