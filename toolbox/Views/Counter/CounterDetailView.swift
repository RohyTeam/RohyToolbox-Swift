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
    @State private var stepText = ""

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
                    HStack {
                        Text("Name")
                        TextField("", text: $counter.name)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Step")
                        TextField("", text: $stepText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .onChange(of: stepText) { _, newValue in
                        // Digits only, and only apply values greater than 0.
                        let filtered = newValue.filter { "0"..."9" ~= $0 }
                        if filtered != newValue {
                            stepText = filtered
                        }
                        if let step = Int(filtered), step > 0 {
                            counter.step = step
                        }
                    }
                }
            }
        }
        .navigationTitle(counter.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            stepText = String(counter.step)
        }
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
    }
}

#Preview {
    NavigationStack {
        CounterDetailView(counter: Counter(name: "计数器 #1", value: 12))
    }
    .modelContainer(for: Counter.self, inMemory: true)
}
