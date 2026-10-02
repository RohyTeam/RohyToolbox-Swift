//
//  ScaleRecord.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Foundation
import SwiftData

@Model
final class ScaleRecord {
    var ratioActual: Int
    var ratioDrawing: Int
    var dpi: Double
    var actualMeters: Double
    var drawingCm: Double
    var createdAt: Date

    init(
        ratioActual: Int,
        ratioDrawing: Int,
        dpi: Double,
        actualMeters: Double,
        drawingCm: Double,
        createdAt: Date = .now
    ) {
        self.ratioActual = ratioActual
        self.ratioDrawing = ratioDrawing
        self.dpi = dpi
        self.actualMeters = actualMeters
        self.drawingCm = drawingCm
        self.createdAt = createdAt
    }
}
