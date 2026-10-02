//
//  RedactionModels.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Observation
import SwiftUI

enum RedactionMode: String, CaseIterable, Identifiable {
    case block
    case blur
    case mosaic

    var id: String { rawValue }

    var name: String {
        switch self {
        case .block: String(localized: "Block")
        case .blur: String(localized: "Blur")
        case .mosaic: String(localized: "Mosaic")
        }
    }

    var icon: String {
        switch self {
        case .block: "square.fill"
        case .blur: "drop.fill"
        case .mosaic: "square.grid.3x3.fill"
        }
    }
}

/// A redaction rectangle, normalized to image size with a top-left origin.
struct RedactionBox: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
    var mode: RedactionMode
    var color: Color
}

/// The box list with undo/redo support.
@Observable
final class RedactionState {
    private(set) var boxes: [RedactionBox] = []
    private var undoStack: [[RedactionBox]] = []
    private var redoStack: [[RedactionBox]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ box: RedactionBox) {
        mutate { $0.append(box) }
    }

    func remove(id: UUID) {
        mutate { $0.removeAll { $0.id == id } }
    }

    func removeAll() {
        mutate { $0.removeAll() }
    }

    /// Live-adjusts a box (drag create / resize); not an undoable mutation.
    func update(id: UUID, rect: CGRect) {
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        boxes[index].rect = rect
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(boxes)
        boxes = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(boxes)
        boxes = next
    }

    private func mutate(_ change: (inout [RedactionBox]) -> Void) {
        undoStack.append(boxes)
        redoStack = []
        change(&boxes)
    }
}
