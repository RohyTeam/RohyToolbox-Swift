//
//  SwiftStoreLiveTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/21.
//

import Testing
@testable import toolbox

/// Hits the real swiftstore-api.deechael.net API.
@MainActor
struct SwiftStoreLiveTests {

    @Test func fetchesCatalogAndDetail() async throws {
        let store = SwiftStore.shared
        await store.refresh()
        try #require(
            !store.apps.isEmpty,
            "refresh failed: \(store.lastError ?? "unknown")"
        )
        let piliPod = try #require(store.apps.first { $0.id == "pilipod" })
        // Summary carries source metadata without version lists.
        #expect(piliPod.sources.isEmpty == false)

        // Detail endpoint delivers full version lists per source.
        let detail = try await store.detail(for: piliPod)
        #expect(detail.versions.isEmpty == false)
        #expect(detail.sources.first?.versions?.isEmpty == false)

        // Single-version endpoint resolves a download URL.
        let url = try await store.downloadURL(for: piliPod)
        #expect(url != nil)
    }
}
