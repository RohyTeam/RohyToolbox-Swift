//
//  ToolboxView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI
import SwiftData

struct ToolboxView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Tools") {
                    NavigationLink {
                        CounterListView()
                    } label: {
                        Label("Counter", systemImage: "number")
                    }
                }
            }
            .navigationTitle("Toolbox")
        }
    }
}

#Preview {
    ToolboxView()
        .modelContainer(for: Counter.self, inMemory: true)
}
