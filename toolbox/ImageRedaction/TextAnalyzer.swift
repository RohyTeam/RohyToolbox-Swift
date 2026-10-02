//
//  TextAnalyzer.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import NaturalLanguage
import UIKit
import Vision

/// A recognized block of text. `rect` is normalized to the image size with a
/// top-left origin (converted from Vision's bottom-left convention).
struct TextBlock: Identifiable {
    private let observation: VNRecognizedTextObservation
    private let candidate: VNRecognizedText
    let text: String
    let rect: CGRect

    var id: ObjectIdentifier { ObjectIdentifier(observation) }

    var isSensitive: Bool {
        SensitiveTextDetector.isSensitive(text)
    }

    init(observation: VNRecognizedTextObservation, candidate: VNRecognizedText) {
        self.observation = observation
        self.candidate = candidate
        self.text = candidate.string
        let box = observation.boundingBox
        self.rect = CGRect(
            x: box.minX,
            y: 1 - box.maxY,
            width: box.width,
            height: box.height
        )
    }

    /// Splits the block into words (NaturalLanguage tokenizer) with their
    /// individual rects, for the long-press word picker.
    func words() -> [(word: String, rect: CGRect)] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [(String, CGRect)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            guard let observation = try? candidate.boundingBox(for: range) else { return true }
            let box = observation.boundingBox
            result.append((
                String(text[range]),
                CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            ))
            return true
        }
        return result
    }
}

/// Runs Vision text recognition, preferring the system language and English.
final class TextAnalyzer {
    func analyze(_ image: UIImage) async -> [TextBlock] {
        guard let cgImage = image.cgImage else { return [] }
        let languages = ["\(Locale.current.language.languageCode?.identifier ?? "zh")-CN", "en-US"]
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let blocks = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> TextBlock? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return TextBlock(observation: observation, candidate: candidate)
                    }
                continuation.resume(returning: blocks)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

/// Detects sensitive content: names, phone numbers, addresses, bank card and
/// ID numbers.
enum SensitiveTextDetector {
    // Chinese mobile numbers.
    private static let phone = try! NSRegularExpression(pattern: #"1[3-9]\d{9}"#)
    // 18-digit ID card numbers.
    private static let idCard = try! NSRegularExpression(pattern: #"\b\d{17}[\dXx]\b"#)
    // Bank card numbers, 16-19 digits.
    private static let bankCard = try! NSRegularExpression(pattern: #"\b\d{16,19}\b"#)

    static func isSensitive(_ text: String) -> Bool {
        matchesStructured(in: text) || containsNameOrPlace(text)
    }

    static func matchesStructured(in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return phone.firstMatch(in: text, range: range) != nil
            || idCard.firstMatch(in: text, range: range) != nil
            || bankCard.firstMatch(in: text, range: range) != nil
    }

    static func containsNameOrPlace(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, _ in
            if tag == .personalName || tag == .placeName {
                found = true
                return false
            }
            return true
        }
        return found
    }
}
