//
//  PhotoLibrary.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import Observation
import Photos

/// Photo library access and asset/album fetching for the Image Redaction tool.
@Observable
final class PhotoLibrary {
    private(set) var authorizationStatus: PHAuthorizationStatus
    private(set) var albums: [PHAssetCollection] = []
    private(set) var assets: [PHAsset] = []
    /// nil means "all photos".
    private(set) var selectedAlbum: PHAssetCollection?

    var hasAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if hasAccess {
            fetchAlbums()
            fetchAssets()
        }
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            fetchAlbums()
            fetchAssets()
        }
    }

    func selectAlbum(_ album: PHAssetCollection?) {
        selectedAlbum = album
        fetchAssets()
    }

    private func fetchAlbums() {
        var result: [PHAssetCollection] = []
        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumUserLibrary, .smartAlbumRecentlyAdded, .smartAlbumFavorites,
            .smartAlbumScreenshots, .smartAlbumSelfPortraits,
        ]
        for subtype in smartSubtypes {
            appendAlbums(PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil
            ), to: &result)
        }
        appendAlbums(PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        ), to: &result)
        albums = result
    }

    private func appendAlbums(
        _ fetchResult: PHFetchResult<PHAssetCollection>,
        to albums: inout [PHAssetCollection]
    ) {
        var collected: [PHAssetCollection] = []
        fetchResult.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            if count > 0 {
                collected.append(collection)
            }
        }
        albums.append(contentsOf: collected)
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult: PHFetchResult<PHAsset>
        if let selectedAlbum {
            let albumOptions = PHFetchOptions()
            albumOptions.sortDescriptors = options.sortDescriptors
            albumOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            fetchResult = PHAsset.fetchAssets(in: selectedAlbum, options: albumOptions)
        } else {
            fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        }
        var items: [PHAsset] = []
        items.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in items.append(asset) }
        assets = items
    }
}
