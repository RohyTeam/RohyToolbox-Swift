//
//  CounterDetailView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI
import SwiftData

struct CounterDetailView: View {
    @Bindable var counter: Counter

    @State private var isEditingValue = false
    @State private var valueInput = ""
    @State private var isEditingName = false
    @State private var nameInput = ""
    @State private var isEditingStep = false
    @State private var stepInput = ""
    @State private var showsInvalidStepAlert = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    counter.value -= counter.step
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                }
                Spacer()
                Button {
                    valueInput = String(counter.value)
                    isEditingValue = true
                } label: {
                    Text(counter.value, format: .number)
                        .font(.system(size: 64, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    counter.value += counter.step
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)

            Form {
                Section {
                    Button {
                        nameInput = counter.name
                        isEditingName = true
                    } label: {
                        infoRow("Name", value: counter.name)
                    }
                    Button {
                        stepInput = String(counter.step)
                        isEditingStep = true
                    } label: {
                        infoRow("Step", value: String(counter.step))
                    }
                }
            }
        }
        .navigationTitle(counter.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Edit Value", isPresented: $isEditingValue) {
            TextField("Value", text: $valueInput)
                .keyboardType(.numbersAndPunctuation)
            Button("OK") {
                if let newValue = Int(valueInput.trimmingCharacters(in: .whitespaces)) {
                    counter.value = newValue
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new value.")
        }
        .alert("Edit Name", isPresented: $isEditingName) {
            TextField("Name", text: $nameInput)
            Button("OK") {
                let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    counter.name = trimmed
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name.")
        }
        .alert("Edit Step", isPresented: $isEditingStep) {
            TextField("Step", text: $stepInput)
                .keyboardType(.numberPad)
                .onChange(of: stepInput) { _, newValue in
                    let filtered = newValue.filter { "0"..."9" ~= $0 }
                    if filtered != newValue {
                        stepInput = filtered
                    }
                }
            Button("OK") {
                if let newStep = Int(stepInput.trimmingCharacters(in: .whitespaces)), newStep > 0 {
                    counter.step = newStep
                } else {
                    showsInvalidStepAlert = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter an integer greater than 0.")
        }
        .alert("Invalid Step", isPresented: $showsInvalidStepAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The step must be an integer greater than 0.")
        }
    }

    private func infoRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }
}

#Preview {
    NavigationStack {
        CounterDetailView(counter: Counter(name: "计数器 #1", value: 12))
    }
    .modelContainer(for: Counter.self, inMemory: true)
}
