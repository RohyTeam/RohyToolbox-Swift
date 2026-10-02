//
//  ScaleConverterView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import SwiftUI
import SwiftData

struct ScaleConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScaleRecord.createdAt, order: .reverse) private var records: [ScaleRecord]

    @State private var ratioActualText = "1"
    @State private var ratioDrawingText = "100"
    @State private var dpiText = "300"
    @State private var useMillimeters = false
    @State private var actualText = ""
    @State private var drawingText = ""
    @State private var lastEdited: ValueField = .actual
    @State private var syncing = false

    private enum ValueField {
        case actual, drawing
    }

    private var ratioActual: Int? { validatedInteger(ratioActualText) }
    private var ratioDrawing: Int? { validatedInteger(ratioDrawingText) }
    private var dpi: Double? {
        guard let value = Double(dpiText), value > 0 else { return nil }
        return value
    }

    private var actualMetersValue: Double? {
        Double(actualText).map { useMillimeters ? $0 / 1000 : $0 }
    }

    private var drawingCmValue: Double? {
        Double(drawingText).map { useMillimeters ? $0 / 10 : $0 }
    }

    private var pixelText: String {
        guard let dpi, let cm = drawingCmValue else { return "—" }
        return "\(ScaleCalculator.pixels(drawingCm: cm, dpi: dpi))"
    }

    private var canAddRecord: Bool {
        ratioActual != nil && ratioDrawing != nil && dpi != nil
            && actualMetersValue != nil && drawingCmValue != nil
    }

    var body: some View {
        Form {
            Section {
                ratioRow
                HStack {
                    Text("DPI")
                    TextField("dpi", text: $dpiText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Millimeter Units", isOn: $useMillimeters)
                    .onChange(of: useMillimeters) { _, newValue in
                        convertUnits(toMillimeters: newValue)
                    }
                valueRow(label: String(localized: "Actual (\(useMillimeters ? "mm" : "m"))"),
                         text: $actualText, field: .actual)
                valueRow(label: String(localized: "Drawing (\(useMillimeters ? "mm" : "cm"))"),
                         text: $drawingText, field: .drawing)
                HStack {
                    Text("Pixels")
                    TextField("px", text: .constant(pixelText))
                        .multilineTextAlignment(.trailing)
                        .disabled(true)
                }
                Button(action: addRecord) {
                    Label("Add Record", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(canAddRecord ? Color.accentColor : Color.secondary)
                }
                .disabled(!canAddRecord)
            }
            if !records.isEmpty {
                Section("Records") {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                }
            }
        }
        .navigationTitle("Scale Converter")
    }

    // MARK: - Rows

    private var ratioRow: some View {
        HStack(spacing: 12) {
            HStack {
                Text("Ratio")
                TextField(String(localized: "Actual"), text: $ratioActualText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity)
            Text(":")
            HStack {
                TextField(String(localized: "Drawing"), text: $ratioDrawingText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: ratioActualText) { _, newValue in
            ratioActualText = digitsOnly(newValue)
            recalcFromLastEdited()
        }
        .onChange(of: ratioDrawingText) { _, newValue in
            ratioDrawingText = digitsOnly(newValue)
            recalcFromLastEdited()
        }
    }

    private func valueRow(label: String, text: Binding<String>, field: ValueField) -> some View {
        HStack {
            Text(label)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        .onChange(of: text.wrappedValue) { _, _ in
            guard !syncing else { return }
            lastEdited = field
            recalc(from: field)
        }
    }

    // MARK: - Calculation

    private func recalc(from field: ValueField) {
        guard let a = ratioActual, let b = ratioDrawing else { return }
        switch field {
        case .actual:
            guard let m = actualMetersValue else { return }
            let cm = ScaleCalculator.drawingCm(actualMeters: m, ratioActual: a, ratioDrawing: b)
            setDrawing(ScaleCalculator.round2(useMillimeters ? cm * 10 : cm))
        case .drawing:
            guard let cm = drawingCmValue else { return }
            let m = ScaleCalculator.actualMeters(drawingCm: cm, ratioActual: a, ratioDrawing: b)
            setActual(ScaleCalculator.round2(useMillimeters ? m * 1000 : m))
        }
    }

    private func recalcFromLastEdited() {
        guard !syncing else { return }
        recalc(from: lastEdited)
    }

    private func setActual(_ value: Double) {
        syncing = true
        actualText = format(value)
        syncing = false
    }

    private func setDrawing(_ value: Double) {
        syncing = true
        drawingText = format(value)
        syncing = false
    }

    private func digitsOnly(_ text: String) -> String {
        text.filter { "0"..."9" ~= $0 }
    }

    private func validatedInteger(_ text: String) -> Int? {
        guard let value = Int(text), value > 0 else { return nil }
        return value
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
    }

    // MARK: - Records

    private func addRecord() {
        guard let a = ratioActual, let b = ratioDrawing, let dpi,
              let m = actualMetersValue, let cm = drawingCmValue else { return }
        modelContext.insert(ScaleRecord(
            ratioActual: a, ratioDrawing: b, dpi: dpi, actualMeters: m, drawingCm: cm
        ))
    }

    private func apply(_ record: ScaleRecord) {
        syncing = true
        defer { syncing = false }
        ratioActualText = "\(record.ratioActual)"
        ratioDrawingText = "\(record.ratioDrawing)"
        dpiText = format(record.dpi)
        actualText = format(useMillimeters ? record.actualMeters * 1000 : record.actualMeters)
        drawingText = format(useMillimeters ? record.drawingCm * 10 : record.drawingCm)
    }

    private func recordRow(_ record: ScaleRecord) -> some View {
        let drawing = useMillimeters ? record.drawingCm * 10 : record.drawingCm
        let actual = useMillimeters ? record.actualMeters * 1000 : record.actualMeters
        let pixels = ScaleCalculator.pixels(drawingCm: record.drawingCm, dpi: record.dpi)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.ratioActual):\(record.ratioDrawing)")
                Text("\(format(record.dpi)) DPI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(format(drawing)) \(useMillimeters ? "mm" : "cm")")
                Text("\(format(actual)) \(useMillimeters ? "mm" : "m") · \(pixels) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            apply(record)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(record)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
        }
    }

    // MARK: - Unit switching

    private func convertUnits(toMillimeters: Bool) {
        syncing = true
        defer { syncing = false }
        if let value = Double(actualText) {
            actualText = format(toMillimeters ? value * 1000 : value / 1000)
        }
        if let value = Double(drawingText) {
            drawingText = format(toMillimeters ? value * 10 : value / 10)
        }
    }
}

#Preview {
    NavigationStack {
        ScaleConverterView()
    }
    .modelContainer(for: ScaleRecord.self, inMemory: true)
}
