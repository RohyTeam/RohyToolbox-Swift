//
//  BoxGestureStateMachineTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/21.
//

import CoreGraphics
import Foundation
import Testing
@testable import toolbox

struct BoxGestureStateMachineTests {

    private let origin = CGPoint(x: 100, y: 100)

    @Test func quickTouchIsTap() {
        let machine = BoxGestureStateMachine()
        let start = Date()
        _ = machine.touchChanged(startLocation: origin, location: origin, translation: .zero, now: start)
        let action = machine.touchEnded(
            location: origin,
            translation: .zero,
            now: start.addingTimeInterval(0.1)
        )
        #expect(action == .tap(location: origin))
    }

    @Test func holdOpensWordPicker() {
        let machine = BoxGestureStateMachine()
        let start = Date()
        _ = machine.touchChanged(startLocation: origin, location: origin, translation: .zero, now: start)
        let action = machine.touchEnded(
            location: origin,
            translation: .zero,
            now: start.addingTimeInterval(0.6)
        )
        #expect(action == .openWordPicker(location: origin))
    }

    @Test func holdAndDragCreatesAndResizesBox() {
        let machine = BoxGestureStateMachine()
        let start = Date()
        let held = start.addingTimeInterval(0.5)
        // Touch down, hold, then drag.
        _ = machine.touchChanged(startLocation: origin, location: origin, translation: .zero, now: start)
        #expect(
            machine.touchChanged(
                startLocation: origin,
                location: CGPoint(x: 120, y: 120),
                translation: CGSize(width: 20, height: 20),
                now: held
            ) == .beginBox(origin: origin)
        )
        #expect(
            machine.touchChanged(
                startLocation: origin,
                location: CGPoint(x: 200, y: 200),
                translation: CGSize(width: 100, height: 100),
                now: held.addingTimeInterval(0.1)
            ) == .resizeBox(to: CGPoint(x: 200, y: 200))
        )
        #expect(
            machine.touchEnded(
                location: CGPoint(x: 200, y: 200),
                translation: CGSize(width: 100, height: 100),
                now: held.addingTimeInterval(0.2)
            ) == .finishBox
        )
        // Next touch starts fresh.
        let next = start.addingTimeInterval(2)
        _ = machine.touchChanged(startLocation: origin, location: origin, translation: .zero, now: next)
        #expect(
            machine.touchEnded(location: origin, translation: .zero, now: next.addingTimeInterval(0.1))
                == .tap(location: origin)
        )
    }

    @Test func quickDragIsNothing() {
        let machine = BoxGestureStateMachine()
        let start = Date()
        _ = machine.touchChanged(
            startLocation: origin,
            location: CGPoint(x: 150, y: 150),
            translation: CGSize(width: 50, height: 50),
            now: start.addingTimeInterval(0.1)
        )
        #expect(
            machine.touchEnded(
                location: CGPoint(x: 150, y: 150),
                translation: CGSize(width: 50, height: 50),
                now: start.addingTimeInterval(0.2)
            ) == .nothing
        )
    }
}
