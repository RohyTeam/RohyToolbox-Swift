//
//  AppIconCacheTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/18.
//

import Testing
import UIKit
@testable import toolbox

struct AppIconCacheTests {

    @Test func downsampleShrinksLargeImages() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let large = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        let data = try #require(large.pngData())

        let thumbnail = try #require(AppIconCache.downsample(data, maxPixelSize: 132))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 132)
    }

    @Test func downsampleRejectsGarbage() {
        #expect(AppIconCache.downsample(Data([0, 1, 2, 3]), maxPixelSize: 132) == nil)
    }
}
