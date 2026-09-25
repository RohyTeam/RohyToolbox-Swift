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

    @Test func mirrorPrefixesDownloadURLs() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "swiftStoreMirror") }
        let url = URL(string: "https://github.com/A/B/releases/download/v1/x.ipa")!

        // Official: untouched.
        defaults.set(StoreMirror.official.rawValue, forKey: "swiftStoreMirror")
        #expect(SwiftStore.applyMirror(to: url) == url)

        defaults.set(StoreMirror.ghProxy.rawValue, forKey: "swiftStoreMirror")
        #expect(
            SwiftStore.applyMirror(to: url).absoluteString
                == "https://gh-proxy.com/https://github.com/A/B/releases/download/v1/x.ipa"
        )
        defaults.set(StoreMirror.ghProxyV4.rawValue, forKey: "swiftStoreMirror")
        #expect(SwiftStore.applyMirror(to: url).absoluteString.hasPrefix("https://v4.gh-proxy.com/"))
        defaults.set(StoreMirror.ghProxyV6.rawValue, forKey: "swiftStoreMirror")
        #expect(SwiftStore.applyMirror(to: url).absoluteString.hasPrefix("https://v6.gh-proxy.com/"))
        defaults.set(StoreMirror.ghProxyFastly.rawValue, forKey: "swiftStoreMirror")
        #expect(SwiftStore.applyMirror(to: url).absoluteString.hasPrefix("https://cdn.gh-proxy.com/"))
        defaults.set(StoreMirror.ghProxyAxisNow.rawValue, forKey: "swiftStoreMirror")
        #expect(SwiftStore.applyMirror(to: url).absoluteString.hasPrefix("https://axisnow.gh-proxy.com/"))
    }
}
