//
//  ScaleCalculator.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Foundation

/// Scale conversion math for the Scale Converter tool.
/// The ratio is written in standard scale notation: `1:100` means 1 cm on
/// the drawing represents 1 m in reality (drawing is 100x smaller).
enum ScaleCalculator {
    static func drawingCm(actualMeters: Double, ratioActual: Int, ratioDrawing: Int) -> Double {
        actualMeters * 100 * Double(ratioActual) / Double(ratioDrawing)
    }

    static func actualMeters(drawingCm: Double, ratioActual: Int, ratioDrawing: Int) -> Double {
        drawingCm / 100 * Double(ratioDrawing) / Double(ratioActual)
    }

    /// Drawing length in cm -> pixels at the given DPI (pixels per inch),
    /// rounded to the nearest integer.
    static func pixels(drawingCm: Double, dpi: Double) -> Int {
        Int((drawingCm / 2.54 * dpi).rounded())
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
