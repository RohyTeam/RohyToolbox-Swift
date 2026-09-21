//
//  CounterListView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI
import SwiftData

struct CounterListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Counter.createdAt) private var counters: [Counter]
    @State private var selectedCounter: Counter?

    var body: some View {
        List {
            ForEach(counters) { counter in
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(counter.value, format: .number)
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                        Text(counter.name)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCounter = counter
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Stepper(value: Binding(
                        get: { counter.value },
                        set: { counter.value = $0 }
                    ), step: counter.step) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation {
                            modelContext.delete(counter)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .navigationTitle("Counter")
        .navigationDestination(item: $selectedCounter) { counter in
            CounterDetailView(counter: counter)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addCounter()
                } label: {
                    Label("Add Counter", systemImage: "plus")
                }
            }
        }
        .overlay {
            if counters.isEmpty {
                ContentUnavailableView {
                    Label("No Counters", systemImage: "number")
                } description: {
                    Text("Tap + to add a counter.")
                }
            }
        }
    }

    private func addCounter() {
        let counter = Counter(name: String(localized: "Counter #\(counters.count + 1)"))
        withAnimation {
            modelContext.insert(counter)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Counter.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(Counter(name: "计数器 #1", value: 12))
    container.mainContext.insert(Counter(name: "计数器 #2", value: 3, step: 5))
    return NavigationStack {
        CounterListView()
    }
    .modelContainer(container)
}
