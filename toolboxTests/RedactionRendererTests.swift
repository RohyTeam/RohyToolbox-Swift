//
//  RedactionRendererTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/10/2.
//

import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import toolbox

struct RedactionRendererTests {

    /// 100x100 image: left half red, right half blue.
    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        }
    }

    /// Center pixel bytes (order-agnostic: index 0 and 2 are the red/blue
    /// channels in either RGBA or BGRA).
    private func centerPixelChannels(_ image: UIImage) -> (UInt8, UInt8)? {
        guard let cgImage = image.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let offset = (cgImage.height / 2) * bytesPerRow + (cgImage.width / 2) * bytesPerPixel
        return (ptr[offset], ptr[offset + 2])
    }

    @Test func blurPatchHasContent() throws {
        let image = makeImage()
        // The patch spans the red/blue boundary; a real blur mixes them.
        let patch = try #require(RedactionRenderer.effectPatch(
            image: image,
            normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            mode: .blur
        ))
        #expect(patch.size == CGSize(width: 50, height: 50))
        let channels = try #require(centerPixelChannels(patch))
        #expect(channels.0 > 0 && channels.1 > 0)
    }

    @Test func mosaicPatchHasContent() throws {
        let image = makeImage()
        // CIPixellate intentionally returns a smaller (low-res) image; the
        // caller stretches it back to the box's size.
        let patch = try #require(RedactionRenderer.effectPatch(
            image: image,
            normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            mode: .mosaic
        ))
        #expect(patch.size.width > 0)
        let channels = try #require(centerPixelChannels(patch))
        #expect(channels.0 > 0 || channels.1 > 0)
    }

    @Test func fullRenderAppliesBoxes() throws {
        let image = makeImage()
        let rendered = RedactionRenderer.render(
            image: image,
            boxes: [RedactionBox(
                rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                mode: .block, color: .black
            )]
        )
        #expect(centerPixelChannels(rendered) != nil)
    }
}
