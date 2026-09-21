//
//  StoreCatalogDecodeTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/21.
//

import Foundation
import Testing
@testable import toolbox

struct StoreCatalogDecodeTests {

    @Test func decodesFixture() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/apps.json")
        let data = try Data(contentsOf: fixture)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(StoreCatalog.self, from: data)
        #expect(catalog.apps.count == 2)
        #expect(catalog.apps[1].sources.first?.name == "DeeChael 源")
        #expect(catalog.apps[1].sources.first?.versions.first?.name == "0.3.6-newui")
    }
}
