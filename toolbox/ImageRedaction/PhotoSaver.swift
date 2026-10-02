//
//  PhotoSaver.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Photos
import SwiftUI
import UIKit

/// Save / delete operations against the photo library, plus share sheet and
/// file exporter presenters.
enum PhotoSaver {
    /// Creates a new asset, leaving the source untouched.
    static func saveCopy(image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    /// Replaces the asset's displayed content via the Photos editing pipeline.
    static func overwrite(asset: PHAsset, data: Data) async throws {
        let input = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: nil) { input, _ in
                if let input {
                    continuation.resume(returning: input)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        try data.write(to: output.renderedContentURL)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.contentEditingOutput = output
        }
    }

    static func delete(_ asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
        }
    }
}

/// System share sheet.
struct ActivityPresenter: UIViewControllerRepresentable {
    let items: [Any]
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// System "save to files" document picker.
struct FileExporter: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
