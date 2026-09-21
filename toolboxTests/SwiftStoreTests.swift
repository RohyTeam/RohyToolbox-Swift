//
//  SwiftStoreTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import Testing
@testable import toolbox

@Suite(.serialized)
struct SwiftStoreTests {

    @Test func listedVersionHonorsBetaSetting() {
        let stable = StoreVersion(
            name: "v1.0.0", size: 1,
            createdAt: Date(timeIntervalSince1970: 1000),
            url: URL(string: "https://example.com/v1.ipa")!
        )
        let beta = StoreVersion(
            name: "v2.0.0-beta", size: 1,
            createdAt: Date(timeIntervalSince1970: 2000),
            url: URL(string: "https://example.com/v2.ipa")!,
            prerelease: true
        )
        let app = StoreApp(
            id: "t", name: "t", description: "", authors: [],
            aiAssisted: false,
            repo: URL(string: "https://example.com")!,
            versions: [stable, beta]
        )

        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "swiftStoreLatestBeta") }

        // Off (default): latest stable.
        defaults.set(false, forKey: "swiftStoreLatestBeta")
        #expect(app.listedVersion == stable)

        // On: latest version including betas.
        defaults.set(true, forKey: "swiftStoreLatestBeta")
        #expect(app.listedVersion == beta)
    }

    @Test func listedVersionFallsBackWhenAllPrerelease() {
        let beta = StoreVersion(
            name: "v1.0.0-beta", size: 1,
            createdAt: Date(timeIntervalSince1970: 1000),
            url: URL(string: "https://example.com/v1.ipa")!,
            prerelease: true
        )
        let app = StoreApp(
            id: "t", name: "t", description: "", authors: [],
            aiAssisted: false,
            repo: URL(string: "https://example.com")!,
            versions: [beta]
        )
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "swiftStoreLatestBeta") }
        defaults.set(false, forKey: "swiftStoreLatestBeta")
        #expect(app.listedVersion == beta)
    }
}
