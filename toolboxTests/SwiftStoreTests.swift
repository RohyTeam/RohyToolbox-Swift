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

    private func makeApp() -> StoreApp {
        StoreApp(
            id: "t", name: "t", description: "", authors: [],
            aiAssisted: false,
            repo: URL(string: "https://example.com")!,
            latestVersion: "v2.0.0-beta",
            latestReleaseVersion: "v1.0.0"
        )
    }

    @Test func listedVersionHonorsBetaSetting() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "swiftStoreLatestBeta") }
        let app = makeApp()

        // Off (default): latest stable release.
        defaults.set(false, forKey: "swiftStoreLatestBeta")
        #expect(app.listedVersionName == "v1.0.0")

        // On: latest version including betas.
        defaults.set(true, forKey: "swiftStoreLatestBeta")
        #expect(app.listedVersionName == "v2.0.0-beta")
    }
}
