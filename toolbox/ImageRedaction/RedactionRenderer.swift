//
//  RedactionRenderer.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import CoreImage
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case original
    case png
    case jpeg

    var id: String { rawValue }

    func name(originalName: String) -> String {
        switch self {
        case .original: String(localized: "Original (\(originalName))")
        case .png: "PNG"
        case .jpeg: "JPG"
        }
    }
}

/// Renders redactions onto images and encodes/saves the results.
enum RedactionRenderer {

    /// Draws all redaction boxes over the image at its native size.
    static func render(image: UIImage, boxes: [RedactionBox]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            for box in boxes {
                let rect = CGRect(
                    x: box.rect.minX * image.size.width,
                    y: box.rect.minY * image.size.height,
                    width: box.rect.width * image.size.width,
                    height: box.rect.height * image.size.height
                )
                switch box.mode {
                case .block:
                    UIColor(box.color).setFill()
                    context.fill(rect)
                case .blur, .mosaic:
                    if let patch = effectPatch(image: image, normalizedRect: box.rect, mode: box.mode) {
                        patch.draw(in: rect)
                    }
                }
            }
        }
    }

    /// Renders one blur/mosaic region as an image. Used both for the live
    /// overlay and the export render so they always match.
    static func effectPatch(image: UIImage, normalizedRect: CGRect, mode: RedactionMode) -> UIImage? {
        guard mode != .block, let cgImage = image.cgImage else { return nil }
        // Normalized (top-left origin) -> pixels (CIImage: bottom-left origin).
        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(cgImage.width),
            y: CGFloat(cgImage.height) - normalizedRect.maxY * CGFloat(cgImage.height),
            width: normalizedRect.width * CGFloat(cgImage.width),
            height: normalizedRect.height * CGFloat(cgImage.height)
        ).integral
        let clamped = CIImage(cgImage: cgImage).clampedToExtent()
        let filtered: CIImage
        if mode == .mosaic {
            // Pixelate the region directly.
            filtered = clamped.cropped(to: pixelRect).applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(8, pixelRect.height / 3),
            ])
        } else {
            // Blur the whole image, then cut the region out: no edge
            // diffusion streaks and text stays unreadable.
            filtered = clamped.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: min(60, max(12, pixelRect.height / 2)),
            ])
            .cropped(to: pixelRect)
        }
        // Move the region to a zero origin before producing a CGImage.
        let output = filtered
            .transformed(by: CGAffineTransform(translationX: -pixelRect.minX, y: -pixelRect.minY))
            .cropped(to: CGRect(origin: .zero, size: pixelRect.size))
        guard let cgOutput = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
    }

    static func data(image: UIImage, boxes: [RedactionBox], format: ExportFormat, originalUTI: String) -> Data? {
        let rendered = render(image: image, boxes: boxes)
        switch format {
        case .png:
            return rendered.pngData()
        case .jpeg:
            return rendered.jpegData(compressionQuality: 0.9)
        case .original:
            if originalUTI == UTType.heic.identifier {
                return heicData(rendered)
            }
            return originalUTI == UTType.png.identifier ? rendered.pngData() : rendered.jpegData(compressionQuality: 0.9)
        }
    }

    private static func heicData(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.heic.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
