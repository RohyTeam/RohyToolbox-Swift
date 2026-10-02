//
//  ScaleCalculatorTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/21.
//

import Foundation
import Testing
@testable import toolbox

struct ScaleCalculatorTests {

    @Test func actualToDrawing() {
        // Standard notation 1:100 -> 1 m in reality is 1 cm on the drawing.
        #expect(ScaleCalculator.drawingCm(actualMeters: 1, ratioActual: 1, ratioDrawing: 100) == 1)
        #expect(ScaleCalculator.drawingCm(actualMeters: 2.5, ratioActual: 1, ratioDrawing: 50) == 5)
    }

    @Test func drawingToActual() {
        #expect(ScaleCalculator.actualMeters(drawingCm: 1, ratioActual: 1, ratioDrawing: 100) == 1)
        #expect(ScaleCalculator.actualMeters(drawingCm: 5, ratioActual: 1, ratioDrawing: 50) == 2.5)
    }

    @Test func pixelsFromDPI() {
        // 2.54 cm is exactly one inch.
        #expect(ScaleCalculator.pixels(drawingCm: 2.54, dpi: 300) == 300)
        // Rounds to the nearest integer.
        #expect(ScaleCalculator.pixels(drawingCm: 1, dpi: 300) == 118)
    }

    @Test func roundingKeepsTwoDecimals() {
        #expect(ScaleCalculator.round2(1.23456) == 1.23)
        #expect(ScaleCalculator.round2(1.235) == 1.24)
        #expect(ScaleCalculator.round2(2.0) == 2.0)
    }
}
