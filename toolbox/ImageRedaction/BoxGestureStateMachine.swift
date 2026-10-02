//
//  BoxGestureStateMachine.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Foundation

/// Touch state machine for the redaction canvas: a quick touch is a tap,
/// a hold opens the word picker, hold-and-drag draws a box. Pure logic,
/// driven by the view's DragGesture callbacks.
final class BoxGestureStateMachine {
    enum Action: Equatable {
        case tap(location: CGPoint)
        case openWordPicker(location: CGPoint)
        case beginBox(origin: CGPoint)
        case resizeBox(to: CGPoint)
        case finishBox
        case nothing
    }

    /// How long a touch must be held before dragging starts a box.
    var holdThreshold: TimeInterval = 0.35
    /// Movement (points) below which a touch counts as not dragged.
    var moveThreshold: CGFloat = 4

    /// True while a touch is being tracked.
    var isTouching: Bool { startTime != nil }

    private var startTime: Date?
    private var creating = false

    /// True while a box is being drawn.
    var isCreating: Bool { creating }

    func touchChanged(startLocation: CGPoint, location: CGPoint, translation: CGSize, now: Date = .now) -> Action {
        if startTime == nil {
            startTime = now
        }
        guard let startTime else { return .nothing }
        let elapsed = now.timeIntervalSince(startTime)
        let moved = hypot(translation.width, translation.height)
        if !creating, elapsed >= holdThreshold, moved > moveThreshold {
            creating = true
            return .beginBox(origin: startLocation)
        }
        if creating {
            return .resizeBox(to: location)
        }
        return .nothing
    }

    func touchEnded(location: CGPoint, translation: CGSize, now: Date = .now) -> Action {
        guard let startTime else { return .nothing }
        defer {
            self.startTime = nil
        }
        let elapsed = now.timeIntervalSince(startTime)
        let moved = hypot(translation.width, translation.height)
        if creating {
            creating = false
            return .finishBox
        }
        if elapsed < holdThreshold, moved < moveThreshold {
            return .tap(location: location)
        }
        if elapsed >= holdThreshold, moved < moveThreshold {
            return .openWordPicker(location: location)
        }
        return .nothing
    }
}
