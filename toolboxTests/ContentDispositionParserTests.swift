//
//  ContentDispositionParserTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import Testing
@testable import toolbox

struct ContentDispositionParserTests {

    @Test func parsesFilenames() {
        // Quoted and bare filename=
        #expect(ContentDispositionParser.fileName(from: "attachment; filename=\"report.zip\"") == "report.zip")
        #expect(ContentDispositionParser.fileName(from: "attachment; filename=report.zip") == "report.zip")
        // RFC 5987 filename*= with percent-encoded UTF-8
        #expect(
            ContentDispositionParser.fileName(
                from: "attachment; filename*=UTF-8''%E4%B8%AD%E6%96%87.zip"
            ) == "中文.zip"
        )
        // filename* wins over filename=
        #expect(
            ContentDispositionParser.fileName(
                from: "attachment; filename=\"a.bin\"; filename*=UTF-8''b.bin"
            ) == "b.bin"
        )
        // Path components are stripped
        #expect(ContentDispositionParser.fileName(from: "attachment; filename=\"/tmp/evil.zip\"") == "evil.zip")
        #expect(ContentDispositionParser.fileName(from: "attachment; filename=\"..\\evil.zip\"") == "evil.zip")
        // No filename at all
        #expect(ContentDispositionParser.fileName(from: "inline") == nil)
        #expect(ContentDispositionParser.fileName(from: "attachment") == nil)
    }
}
