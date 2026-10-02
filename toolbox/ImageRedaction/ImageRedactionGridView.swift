//
//  ImageRedactionGridView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Photos
import SwiftUI

struct ImageRedactionGridView: View {
    @State private var library = PhotoLibrary()
    @Namespace private var namespace
    @State private var selectedAsset: PHAsset?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        Group {
            switch library.authorizationStatus {
            case .authorized, .limited:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(library.assets, id: \.localIdentifier) { asset in
                            AssetThumbnail(asset: asset)
                                .matchedTransitionSource(id: asset.localIdentifier, in: namespace)
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                        }
                    }
                }
            case .notDetermined:
                ProgressView()
                    .task {
                        await library.requestAccess()
                    }
            default:
                ContentUnavailableView {
                    Label("Full Photo Access Needed", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Full photo library access is required to redact images.")
                } actions: {
                    Button {
                        if library.authorizationStatus == .notDetermined {
                            Task { await library.requestAccess() }
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Grant Access")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle(library.selectedAlbum?.localizedTitle ?? String(localized: "All"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedAsset) { asset in
            ImageRedactionView(asset: asset)
                .navigationTransition(.zoom(sourceID: asset.localIdentifier, in: namespace))
        }
        .toolbar {
            ToolbarTitleMenu {
                Button {
                    library.selectAlbum(nil)
                } label: {
                    Label("All", systemImage: "photo.on.rectangle")
                }
                ForEach(library.albums, id: \.localIdentifier) { album in
                    Button(album.localizedTitle ?? "") {
                        library.selectAlbum(album)
                    }
                }
            }
        }
    }
}

private struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityIdentifier("asset-cell")
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                let size = CGSize(width: 300, height: 300)
                image = await withCheckedContinuation { continuation in
                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: size,
                        contentMode: .aspectFill,
                        options: nil
                    ) { image, _ in
                        continuation.resume(returning: image)
                    }
                }
            }
    }
}

#Preview {
    NavigationStack {
        ImageRedactionGridView()
    }
}
