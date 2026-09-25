//
//  SwiftStore.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import ImageIO
import Observation
import UIKit

/// Two-layer (memory + disk) cache for store app icons, independent of
/// server cache headers. Downloads are downscaled once to thumbnail size so
/// rendering stays cheap, and failures are remembered briefly to avoid
/// refetching broken icons on every refresh.
final class AppIconCache {
    static let shared = AppIconCache()

    private var memory: [URL: UIImage] = [:]
    private var failures: [URL: Date] = [:]
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    /// How long a failed icon is not retried.
    private static let failureTTL: TimeInterval = 300
    /// 44pt @3x.
    private static let thumbnailPixelSize = 132

    private init() {}

    func image(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = memory[url] { return cached }
        if let failedAt = failures[url], Date().timeIntervalSince(failedAt) < Self.failureTTL {
            return nil
        }
        if let task = inFlight[url] { return await task.value }

        let file = cacheDirectory.appendingPathComponent(url.lastPathComponent)
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                return image
            }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = Self.downsample(data, maxPixelSize: Self.thumbnailPixelSize) else {
                return nil
            }
            try? image.pngData()?.write(to: file, options: .atomic)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory[url] = image
        } else {
            failures[url] = Date()
        }
        return image
    }

    /// Decodes `data` into a thumbnail no larger than `maxPixelSize` points
    /// on either side.
    static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private var cacheDirectory: URL {
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app-icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct StoreVersion: Codable, Hashable {
    var name: String
    var size: Int64
    var createdAt: Date
    var url: URL
    var prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case name, size, url, prerelease
        case createdAt = "created_at"
    }

    init(name: String, size: Int64, createdAt: Date, url: URL, prerelease: Bool = false) {
        self.name = name
        self.size = size
        self.createdAt = createdAt
        self.url = url
        self.prerelease = prerelease
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int64.self, forKey: .size)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        url = try container.decode(URL.self, forKey: .url)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }
}

/// A download source. In the apps list it only carries summary fields;
/// full version lists arrive with the app detail.
struct StoreSource: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var repo: URL?
    var latestVersion: String?
    var latestReleaseVersion: String?
    var versions: [StoreVersion]?

    enum CodingKeys: String, CodingKey {
        case id, name, repo, versions
        case latestVersion = "latest-version"
        case latestReleaseVersion = "latest-release-version"
    }
}

/// An app entry in the store list (from apps.json). Version lists are
/// fetched separately per app.
struct StoreApp: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
    var authors: [String]
    var aiAssisted: Bool
    var repo: URL
    var latestVersion: String
    var latestReleaseVersion: String
    var sources: [StoreSource]

    enum CodingKeys: String, CodingKey {
        case id, name, description, authors, repo, sources
        case aiAssisted = "ai-assisted"
        case latestVersion = "latest-version"
        case latestReleaseVersion = "latest-release-version"
    }

    init(
        id: String, name: String, description: String, authors: [String],
        aiAssisted: Bool, repo: URL, latestVersion: String,
        latestReleaseVersion: String, sources: [StoreSource] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.authors = authors
        self.aiAssisted = aiAssisted
        self.repo = repo
        self.latestVersion = latestVersion
        self.latestReleaseVersion = latestReleaseVersion
        self.sources = sources
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        authors = try container.decode([String].self, forKey: .authors)
        aiAssisted = try container.decode(Bool.self, forKey: .aiAssisted)
        repo = try container.decode(URL.self, forKey: .repo)
        latestVersion = try container.decode(String.self, forKey: .latestVersion)
        latestReleaseVersion = try container.decode(String.self, forKey: .latestReleaseVersion)
        sources = try container.decodeIfPresent([StoreSource].self, forKey: .sources) ?? []
    }

    /// The version name shown in (and downloaded from) the list. Honors the
    /// "latest beta" setting: off (default) uses the latest stable release,
    /// on uses the latest version including prereleases.
    var listedVersionName: String {
        UserDefaults.standard.bool(forKey: "swiftStoreLatestBeta")
            ? latestVersion
            : latestReleaseVersion
    }

    func iconURL(dark: Bool) -> URL? {
        SwiftStore.baseURL
            .appendingPathComponent("icons/\(id)_\(dark ? "dark" : "light").png")
    }
}

/// Full app detail from /app/{id}/versions.json.
struct StoreAppDetail: Codable, Hashable {
    var versions: [StoreVersion]
    var sources: [StoreSource]
}

struct StoreCatalog: Codable {
    var updatedAt: Date
    var apps: [StoreApp]

    enum CodingKeys: String, CodingKey {
        case apps
        case updatedAt = "updated_at"
    }
}

/// Fetches the Swift Store catalog and caches it on disk; cached content is
/// shown immediately while a refresh is in flight.
@Observable
final class SwiftStore {
    static let shared = SwiftStore()

    private(set) var apps: [StoreApp] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    /// The last refresh error, for diagnostics.
    private(set) var lastError: String?

    private var hasLoadedOnce = false
    private var loadTask: Task<Void, Never>?

    private static let defaultBaseURL = URL(string: "https://swiftstore-api.deechael.net")!

    /// The API base URL, overridable via the `-storeEndpoint` launch
    /// argument (used by UI tests to hit a local fixture server).
    static var baseURL: URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-storeEndpoint"),
           arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1]) {
            return url.deletingLastPathComponent()
        }
        return defaultBaseURL
    }

    private init() {}

    /// Loads the cached catalog, then refreshes from the server in an
    /// unstructured task so it is not cancelled when the view's `.task`
    /// scope ends (e.g. TabView recreating tab content). A failed first
    /// refresh is retried once.
    func load() {
        guard loadTask == nil else { return }
        if !hasLoadedOnce {
            hasLoadedOnce = true
            loadCache()
        }
        loadTask = Task {
            await refresh()
            if apps.isEmpty && loadFailed {
                try? await Task.sleep(for: .seconds(1.5))
                await refresh()
            }
            loadTask = nil
        }
    }

    /// Refreshes from the server. Concurrent refreshes are ignored so a
    /// failing overlapping request can't flash the error state while
    /// another one is still loading.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            var request = URLRequest(url: Self.baseURL.appendingPathComponent("apps.json"))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            apps = try Self.decoder().decode(StoreCatalog.self, from: data).apps
            try? data.write(to: cacheURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            loadFailed = apps.isEmpty
        }
    }

    /// Fetches the full version list (official + all sources) for an app.
    func detail(for app: StoreApp) async throws -> StoreAppDetail {
        let url = Self.baseURL.appendingPathComponent("app/\(app.id)/versions.json")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try Self.decoder().decode(StoreAppDetail.self, from: data)
    }

    /// Resolves the download URL of the app's listed version.
    func downloadURL(for app: StoreApp) async throws -> URL? {
        let name = app.listedVersionName
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = Self.baseURL
            .appendingPathComponent("app/\(app.id)/official/\(encoded).json")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try Self.decoder().decode(StoreVersion.self, from: data).url
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let catalog = try? Self.decoder().decode(StoreCatalog.self, from: data) else { return }
        apps = catalog.apps
    }

    private var cacheURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("swiftstore-apps.json")
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
