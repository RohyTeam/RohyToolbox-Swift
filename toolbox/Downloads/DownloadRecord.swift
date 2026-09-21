//
//  DownloadRecord.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import SwiftData

enum DownloadState: String, Codable {
    case waiting
    case downloading
    case paused
    case completed
    case failed
}

@Model
final class DownloadRecord {
    @Attribute(.unique) var id: UUID
    var urlString: String
    var fileName: String
    var headers: [String: String]
    var state: DownloadState
    var totalBytes: Int64?
    var supportsRange: Bool
    var requestedSegments: Int
    var segmentBytes: [Int64]
    var segmentTotals: [Int64]
    var segmentTimes: [TimeInterval]
    var segmentRequestBases: [Int64]
    var segmentResumeBases: [Int64]
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        urlString: String,
        fileName: String,
        headers: [String: String] = [:],
        state: DownloadState = .waiting,
        totalBytes: Int64? = nil,
        supportsRange: Bool = false,
        requestedSegments: Int,
        segmentBytes: [Int64] = [],
        segmentTotals: [Int64] = [],
        segmentTimes: [TimeInterval] = [],
        segmentRequestBases: [Int64] = [],
        segmentResumeBases: [Int64] = [],
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorMessage: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.urlString = urlString
        self.fileName = fileName
        self.headers = headers
        self.state = state
        self.totalBytes = totalBytes
        self.supportsRange = supportsRange
        self.requestedSegments = requestedSegments
        self.segmentBytes = segmentBytes
        self.segmentTotals = segmentTotals
        self.segmentTimes = segmentTimes
        self.segmentRequestBases = segmentRequestBases
        self.segmentResumeBases = segmentResumeBases
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}
