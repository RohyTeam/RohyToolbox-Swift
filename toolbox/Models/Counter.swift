//
//  Counter.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import SwiftData

@Model
final class Counter {
    var name: String
    var value: Int
    var step: Int
    var createdAt: Date

    init(name: String, value: Int = 0, step: Int = 1, createdAt: Date = .now) {
        self.name = name
        self.value = value
        self.step = step
        self.createdAt = createdAt
    }
}
