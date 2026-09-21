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

    @Test func fetchesCatalog() async throws {
        let store = SwiftStore.shared
        await store.refresh()
        try #require(
            !store.apps.isEmpty,
            "refresh failed: \(store.lastError ?? "unknown")"
        )
        #expect(store.apps.contains { $0.id == "pilipod" })
        let piliPod = store.apps.first { $0.id == "pilipod" }
        #expect(piliPod?.sources.isEmpty == false)
        #expect(piliPod?.sources.first?.versions.isEmpty == false)
    }
}
