//
//  SensitiveTextDetectorTests.swift
//  toolboxTests
//
//  Created by Deerio on 2026/9/21.
//

import Testing
@testable import toolbox

struct SensitiveTextDetectorTests {

    @Test func detectsPhoneNumbers() {
        #expect(SensitiveTextDetector.matchesStructured(in: "联系电话 13812345678 谢谢"))
        #expect(!SensitiveTextDetector.matchesStructured(in: "编号 12345"))
    }

    @Test func detectsIDCards() {
        #expect(SensitiveTextDetector.matchesStructured(in: "身份证号 11010519491231002X"))
        #expect(!SensitiveTextDetector.matchesStructured(in: "20260921"))
    }

    @Test func detectsBankCards() {
        #expect(SensitiveTextDetector.matchesStructured(in: "卡号 6222021234567890123"))
        #expect(!SensitiveTextDetector.matchesStructured(in: "数量 1234"))
    }

    @Test func detectsNamesAndPlaces() {
        // The simulator's NLTagger NER model tags everything as .other;
        // this assertion is only meaningful on real devices.
        #if targetEnvironment(simulator)
        return
        #endif
        #expect(SensitiveTextDetector.containsNameOrPlace("张三"))
        #expect(SensitiveTextDetector.containsNameOrPlace("Bill Gates"))
        #expect(!SensitiveTextDetector.containsNameOrPlace("手机"))
    }
}
