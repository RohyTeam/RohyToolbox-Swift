//
//  ContentDispositionParser.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import Foundation

/// Extracts the suggested file name from a Content-Disposition header,
/// supporting both `filename="a.zip"` and RFC 5987 `filename*=UTF-8''...`
/// forms (the latter wins).
enum ContentDispositionParser {
    static func fileName(from header: String) -> String? {
        var fallback: String?
        for part in header.split(separator: ";").dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            var value = pair[1].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if key == "filename*" {
                // RFC 5987: charset''percent-encoded-value
                if let range = value.range(of: "''"),
                   let decoded = String(value[range.upperBound...]).removingPercentEncoding,
                   let name = sanitize(decoded) {
                    return name
                }
            } else if key == "filename" {
                fallback = sanitize(value)
            }
        }
        return fallback
    }

    /// Strips path components and rejects empty/dot names.
    private static func sanitize(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last.map(String.init) ?? ""
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return nil }
        return cleaned
    }
}
