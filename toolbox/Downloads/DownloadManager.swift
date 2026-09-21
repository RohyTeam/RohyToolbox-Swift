//
//  DownloadManager.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import Foundation
import Observation
import SwiftData

@Observable
final class DownloadTask: Identifiable {
    let record: DownloadRecord

    var state: DownloadState
    var totalBytes: Int64?
    var supportsRange: Bool
    var segmentBytes: [Int64]
    var segmentTotals: [Int64]
    var segmentTimes: [TimeInterval]
    /// Bytes of each segment that were already on disk when its current
    /// request was created.
    var segmentRequestBases: [Int64]
    /// The `totalBytesWritten` offset each segment's request was resumed at.
    var segmentResumeBases: [Int64]
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?
    var speed: Double = 0

    var session: URLSession?
    var sessionTasks: [Int: URLSessionDownloadTask] = [:]
    var finishedSegments = 0
    var segmentActiveDates: [Date?] = []
    var bytesSinceSample: Int64 = 0
    var lastSampleDate = Date()
    var lastPersistDate = Date.distantPast
    /// Order used when picking a victim to pause for "start now".
    /// `Date.distantPast` means protected (considered the earliest started).
    var startOrder = Date.distantPast

    let id: UUID
    let urlString: String
    var fileName: String
    let requestedSegments: Int
    /// True when the name was chosen explicitly (custom name or a
    /// Content-Disposition suggestion from the browser) and must not be
    /// overridden by the probe.
    var hasCustomFileName = false
    /// Extra request headers captured when the task was created
    /// (e.g. Cookie / User-Agent from the in-app browser).
    let headers: [String: String]
    var url: URL? { URL(string: urlString) }
    var downloadedBytes: Int64 { segmentBytes.reduce(0, +) }
    var isSegmented: Bool { segmentBytes.count > 1 }

    init(record: DownloadRecord) {
        self.record = record
        self.id = record.id
        self.urlString = record.urlString
        self.fileName = record.fileName
        self.requestedSegments = record.requestedSegments
        self.headers = record.headers
        self.state = record.state == .downloading ? .waiting : record.state
        self.totalBytes = record.totalBytes
        self.supportsRange = record.supportsRange
        self.segmentBytes = record.segmentBytes
        self.segmentTotals = record.segmentTotals
        self.segmentTimes = record.segmentTimes
        self.segmentRequestBases = record.segmentRequestBases
        self.segmentResumeBases = record.segmentResumeBases
        self.startedAt = record.startedAt
        self.finishedAt = record.finishedAt
        self.errorMessage = record.errorMessage
    }
}

extension DownloadTask: Hashable {
    static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    private(set) var tasks: [DownloadTask] = []

    /// The task currently shown in the popup bar (set by its detail page).
    var popupTaskID: UUID?

    var popupTask: DownloadTask? {
        tasks.first { $0.id == popupTaskID }
    }

    var activeTasks: [DownloadTask] { tasks.filter { $0.state != .completed } }
    var completedTasks: [DownloadTask] { tasks.filter { $0.state == .completed } }
    /// Number of tasks currently downloading, shown as the tab badge.
    var downloadingCount: Int { tasks.filter { $0.state == .downloading }.count }
    var hasDownloadingTasks: Bool { tasks.contains { $0.state == .downloading } }
    var hasPausedTasks: Bool { tasks.contains { $0.state == .paused } }

    private var context: ModelContext?
    private var pumpSuppressed = false

    init() {}

    /// Loads persisted records and resumes interrupted downloads.
    /// Called once from the root view; later calls are ignored.
    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context

        let descriptor = FetchDescriptor<DownloadRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        tasks = records.map(DownloadTask.init(record:))

        // Downloads interrupted by quitting the app go back into the queue
        // and resume from their partial files.
        for task in tasks where task.record.state == .downloading {
            task.state = .waiting
            task.record.state = .waiting
        }
        save()
        pump()
    }

    // MARK: - Task queue

    func add(url: URL, headers: [String: String] = [:], fileName: String? = nil) {
        guard let context else { return }
        let trimmed = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasCustomName = !trimmed.isEmpty
        let record = DownloadRecord(
            urlString: url.absoluteString,
            fileName: hasCustomName ? uniqueFileName(suggested: trimmed) : uniqueFileName(for: url),
            headers: headers,
            requestedSegments: setting("downloadSegmentCount", min: 1, max: 16, fallback: 4)
        )
        context.insert(record)
        save()
        let task = DownloadTask(record: record)
        task.hasCustomFileName = hasCustomName
        tasks.insert(task, at: 0)
        pump()
    }

    func delete(_ task: DownloadTask, removeFile: Bool) {
        task.session?.invalidateAndCancel()
        task.session = nil
        cleanupParts(of: task)
        if removeFile {
            try? FileManager.default.removeItem(at: destinationURL(of: task))
        }
        context?.delete(task.record)
        save()
        tasks.removeAll { $0.id == task.id }
        if popupTaskID == task.id {
            popupTaskID = nil
        }
        pump()
    }

    /// Pauses a downloading task. In-flight segments are cancelled with
    /// resume data, which is stored on disk so nothing downloaded is lost.
    func pause(_ task: DownloadTask) {
        guard task.state == .downloading else { return }
        stopTiming(task)
        task.state = .paused
        task.speed = 0

        let sessionTasks = task.sessionTasks
        task.sessionTasks = [:]
        for index in sessionTasks.keys.sorted()
        where task.segmentBytes.indices.contains(index) && task.segmentRequestBases.indices.contains(index) {
            task.segmentResumeBases[index] = task.segmentBytes[index] - task.segmentRequestBases[index]
        }
        syncRecord(task)
        save()
        pump()

        let taskID = task.id
        for (index, downloadTask) in sessionTasks {
            downloadTask.cancel(byProducingResumeData: { data in
                Task { @MainActor [weak self] in
                    self?.storeResumeData(data, taskID: taskID, segment: index)
                }
            })
        }
        task.session?.finishTasksAndInvalidate()
        task.session = nil
    }

    /// Persists resume data captured on pause. Dropped if the task has
    /// already been resumed or deleted in the meantime.
    func storeResumeData(_ data: Data?, taskID: UUID, segment: Int) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              task.state == .paused else { return }
        guard let data else { return }
        try? data.write(to: resumeDataURL(of: task, segment: segment), options: .atomic)
    }

    /// Puts a failed task back into the queue; it resumes from its part files.
    func retry(_ task: DownloadTask) {
        guard task.state == .failed else { return }
        task.errorMessage = nil
        task.state = .waiting
        syncRecord(task)
        save()
        pump()
    }

    /// Resumes a paused task by putting it back into the queue.
    func resume(_ task: DownloadTask) {
        guard task.state == .paused else { return }
        task.state = .waiting
        syncRecord(task)
        save()
        pump()
    }

    func pauseAll() {
        pumpSuppressed = true
        for task in tasks where task.state == .downloading {
            pause(task)
        }
        pumpSuppressed = false
    }

    func resumeAllPaused() {
        for task in tasks where task.state == .paused {
            task.state = .waiting
            syncRecord(task)
        }
        save()
        pump()
    }

    /// Starts a waiting task immediately. If the concurrency limit is reached,
    /// the most recently started downloading task is paused to free a slot.
    /// The started task is marked as the earliest-started one (without
    /// touching its real start time) so a later "start now" won't pause it.
    func startNow(_ task: DownloadTask) {
        guard task.state == .waiting else { return }
        let maxConcurrent = setting("maxConcurrentDownloads", min: 1, max: 10, fallback: 4)
        var running = tasks.filter { $0.state == .downloading }
        if running.count >= maxConcurrent, let victim = running.max(by: { $0.startOrder < $1.startOrder }) {
            pumpSuppressed = true
            pause(victim)
            pumpSuppressed = false
            running = tasks.filter { $0.state == .downloading }
        }
        if task.startedAt == nil {
            task.startedAt = Date()
        }
        task.startOrder = (running.map(\.startOrder).min() ?? Date()).addingTimeInterval(-1)
        task.state = .downloading
        syncRecord(task)
        save()
        Task { await start(task) }
    }

    /// Toggles between pause and resume; waiting tasks start immediately.
    func toggle(_ task: DownloadTask) {
        switch task.state {
        case .downloading: pause(task)
        case .paused: resume(task)
        case .waiting: startNow(task)
        case .completed, .failed: break
        }
    }

    private func pump() {
        guard !pumpSuppressed else { return }
        let maxConcurrent = setting("maxConcurrentDownloads", min: 1, max: 10, fallback: 4)
        let running = tasks.filter { $0.state == .downloading }.count
        var slots = max(0, maxConcurrent - running)
        for task in tasks where task.state == .waiting && slots > 0 {
            if task.startedAt == nil {
                task.startedAt = Date()
            }
            task.startOrder = Date()
            task.state = .downloading
            syncRecord(task)
            slots -= 1
            Task { await start(task) }
        }
    }

    // MARK: - Downloading

    private func start(_ task: DownloadTask) async {
        if task.totalBytes == nil, !task.supportsRange {
            await probe(task)
        }
        guard isAlive(task), task.url != nil else { return }

        if task.supportsRange, let total = task.totalBytes, total > 0 {
            startSegmented(task, total: total)
        } else {
            startSingle(task)
        }
    }

    /// Probes range support with a `Range: bytes=0-0` GET. A HEAD request is
    /// not an option: S3-presigned URLs (e.g. GitHub release assets) are
    /// signed per HTTP method and reject HEAD with 403. The body stream is
    /// cancelled after the first chunk, so the file is not downloaded.
    private func probe(_ task: DownloadTask) async {
        guard let url = task.url else { return }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 15
        applyHeaders(of: task, to: &request)
        guard let (stream, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse else { return }
        var iterator = stream.makeAsyncIterator()
        _ = try? await iterator.next()

        if http.statusCode == 206,
           let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let total = Self.contentRangeTotal(contentRange), total > 0 {
            task.totalBytes = total
            task.supportsRange = true
        } else {
            if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init), length > 0 {
                task.totalBytes = length
            }
            task.supportsRange = false
        }
        // The server may suggest a file name via Content-Disposition.
        if !task.hasCustomFileName,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           let suggested = ContentDispositionParser.fileName(from: disposition),
           suggested != task.fileName {
            let unique = uniqueFileName(suggested: suggested)
            task.fileName = unique
            task.record.fileName = unique
        }
        syncRecord(task)
    }

    /// Parses the total size out of `Content-Range: bytes 0-0/12345`.
    private static func contentRangeTotal(_ value: String) -> Int64? {
        guard let slash = value.lastIndex(of: "/") else { return nil }
        return Int64(value[value.index(after: slash)...])
    }

    private func makeSession(for task: DownloadTask) -> URLSession {
        let session = URLSession(
            configuration: .default,
            delegate: DownloadSessionDelegate(taskID: task.id, manager: self),
            delegateQueue: nil
        )
        task.session = session
        return session
    }

    /// Whole-file download. Used when the server does not support ranges;
    /// resumes via resume data if available, otherwise restarts from zero.
    private func startSingle(_ task: DownloadTask) {
        guard let url = task.url else { return }
        if task.segmentBytes.count != 1 {
            cleanupParts(of: task)
            task.segmentBytes = [0]
            task.segmentRequestBases = [0]
            task.segmentResumeBases = [0]
        }
        task.segmentTotals = []
        if task.segmentTimes.count != 1 {
            task.segmentTimes = [0]
        }
        task.segmentActiveDates = [Date()]
        task.sessionTasks = [:]

        let session = makeSession(for: task)
        let resumeURL = resumeDataURL(of: task, segment: 0)
        let downloadTask: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeURL) {
            try? FileManager.default.removeItem(at: resumeURL)
            downloadTask = session.downloadTask(withResumeData: data)
        } else {
            task.segmentRequestBases = [0]
            task.segmentResumeBases = [0]
            var request = URLRequest(url: url)
            applyHeaders(of: task, to: &request)
            downloadTask = session.downloadTask(with: request)
        }
        downloadTask.taskDescription = "0"
        task.sessionTasks[0] = downloadTask
        downloadTask.resume()
        syncRecord(task)
    }

    /// Range download split into N part files. Resumes each segment from the
    /// size of its part file already on disk.
    private func startSegmented(_ task: DownloadTask, total: Int64) {
        guard let url = task.url else { return }
        let count = min(max(task.requestedSegments, 1), Int(total))
        let base = total / Int64(count)
        var offset: Int64 = 0
        var ranges: [(offset: Int64, length: Int64)] = []
        for index in 0..<count {
            let length = index == count - 1 ? total - offset : base
            ranges.append((offset, length))
            offset += length
        }
        // The segment layout changed (e.g. segment count setting): any data
        // on disk belongs to the old layout and must be discarded.
        if task.segmentBytes.count != count || task.segmentTotals != ranges.map(\.length) {
            cleanupParts(of: task)
            task.segmentBytes = [Int64](repeating: 0, count: count)
            task.segmentRequestBases = [Int64](repeating: 0, count: count)
            task.segmentResumeBases = [Int64](repeating: 0, count: count)
            task.segmentTimes = [TimeInterval](repeating: 0, count: count)
        }
        if task.segmentTimes.count != count {
            task.segmentTimes = [TimeInterval](repeating: 0, count: count)
        }
        task.segmentTotals = ranges.map(\.length)
        task.finishedSegments = 0

        let fm = FileManager.default
        let session = makeSession(for: task)
        task.sessionTasks = [:]
        task.segmentActiveDates = [Date?](repeating: nil, count: count)
        var pending = 0
        for (index, range) in ranges.enumerated() {
            let part = partURL(of: task, segment: index)
            var have = (try? fm.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0
            if have > range.length {
                try? fm.removeItem(at: part)
                have = 0
            }
            task.segmentBytes[index] = have
            if have >= range.length {
                task.finishedSegments += 1
                continue
            }
            let downloadTask: URLSessionDownloadTask
            let resumeURL = resumeDataURL(of: task, segment: index)
            if let data = try? Data(contentsOf: resumeURL) {
                // Resume exactly where this segment was paused.
                try? fm.removeItem(at: resumeURL)
                downloadTask = session.downloadTask(withResumeData: data)
            } else {
                task.segmentRequestBases[index] = have
                task.segmentResumeBases[index] = 0
                var request = URLRequest(url: url)
                request.setValue(
                    "bytes=\(range.offset + have)-\(range.offset + range.length - 1)",
                    forHTTPHeaderField: "Range"
                )
                applyHeaders(of: task, to: &request)
                downloadTask = session.downloadTask(with: request)
            }
            downloadTask.taskDescription = String(index)
            task.sessionTasks[index] = downloadTask
            task.segmentActiveDates[index] = Date()
            downloadTask.resume()
            pending += 1
        }
        syncRecord(task)
        if pending == 0 {
            joinSegments(of: task)
        }
    }

    // MARK: - Session delegate callbacks

    func task(_ id: UUID, segment: Int, didWriteBytes delta: Int64, totalWritten: Int64, expectedTotal: Int64) {
        guard let task = tasks.first(where: { $0.id == id }),
              task.state == .downloading,
              task.segmentBytes.indices.contains(segment) else { return }
        let requestBase = task.segmentRequestBases.indices.contains(segment)
            ? task.segmentRequestBases[segment] : 0
        let resumeBase = task.segmentResumeBases.indices.contains(segment)
            ? task.segmentResumeBases[segment] : 0
        task.segmentBytes[segment] = requestBase + totalWritten - resumeBase
        if task.totalBytes == nil, expectedTotal > 0 {
            task.totalBytes = expectedTotal
        }
        let now = Date()
        if task.segmentTimes.indices.contains(segment) {
            if task.segmentActiveDates.indices.contains(segment), let since = task.segmentActiveDates[segment] {
                task.segmentTimes[segment] += now.timeIntervalSince(since)
            }
            task.segmentActiveDates[segment] = now
        }
        task.bytesSinceSample += delta
        let interval = now.timeIntervalSince(task.lastSampleDate)
        if interval >= 0.5 {
            task.speed = Double(task.bytesSinceSample) / interval
            task.bytesSinceSample = 0
            task.lastSampleDate = now
        }
        // Persist progress at most every 2 seconds.
        if now.timeIntervalSince(task.lastPersistDate) >= 2 {
            task.lastPersistDate = now
            syncRecord(task)
            save()
        }
    }

    func task(_ id: UUID, segment: Int, didFinishTo staging: URL) {
        guard let task = tasks.first(where: { $0.id == id }), task.state == .downloading else {
            try? FileManager.default.removeItem(at: staging)
            return
        }
        task.sessionTasks[segment] = nil
        if task.isSegmented {
            let part = partURL(of: task, segment: segment)
            let mustAppend = FileManager.default.fileExists(atPath: part.path)
            Task.detached(priority: .utility) {
                do {
                    try Self.merge(staging: staging, into: part, append: mustAppend)
                    await MainActor.run { self.segmentPersisted(taskID: id, segment: segment) }
                } catch {
                    await MainActor.run { self.failTask(with: id, message: error.localizedDescription) }
                }
            }
        } else {
            do {
                let destination = destinationURL(of: task)
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: staging, to: destination)
                finish(task)
            } catch {
                fail(task, message: error.localizedDescription)
            }
        }
    }

    func task(_ id: UUID, didFailWithError error: Error) {
        guard let task = tasks.first(where: { $0.id == id }),
              task.state == .downloading else { return }
        fail(task, message: error.localizedDescription)
    }

    private func segmentPersisted(taskID: UUID, segment: Int) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              task.state == .downloading else { return }
        if task.segmentActiveDates.indices.contains(segment), let since = task.segmentActiveDates[segment] {
            task.segmentTimes[segment] += Date().timeIntervalSince(since)
            task.segmentActiveDates[segment] = nil
        }
        task.finishedSegments += 1
        syncRecord(task)
        save()
        if task.finishedSegments == task.segmentBytes.count {
            joinSegments(of: task)
        }
    }

    // MARK: - Completion

    /// Appends or moves a finished (remaining) download into its part file.
    nonisolated private static func merge(staging: URL, into part: URL, append: Bool) throws {
        let fm = FileManager.default
        if append {
            let writer = try FileHandle(forWritingTo: part)
            try writer.seekToEnd()
            let reader = try FileHandle(forReadingFrom: staging)
            while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
                try writer.write(contentsOf: chunk)
            }
            try reader.close()
            try writer.close()
            try fm.removeItem(at: staging)
        } else {
            try fm.moveItem(at: staging, to: part)
        }
    }

    private func joinSegments(of task: DownloadTask) {
        let partURLs = task.segmentBytes.indices.map { partURL(of: task, segment: $0) }
        let destination = destinationURL(of: task)
        let id = task.id
        Task.detached(priority: .utility) {
            do {
                let fm = FileManager.default
                if partURLs.count == 1, let only = partURLs.first {
                    try fm.moveItem(at: only, to: destination)
                } else {
                    fm.createFile(atPath: destination.path, contents: nil)
                    let writer = try FileHandle(forWritingTo: destination)
                    for part in partURLs {
                        let reader = try FileHandle(forReadingFrom: part)
                        while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
                            try writer.write(contentsOf: chunk)
                        }
                        try reader.close()
                        try fm.removeItem(at: part)
                    }
                    try writer.close()
                }
                await MainActor.run { self.finishTask(with: id) }
            } catch {
                await MainActor.run { self.failTask(with: id, message: error.localizedDescription) }
            }
        }
    }

    private func finishTask(with id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        finish(task)
    }

    private func failTask(with id: UUID, message: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        fail(task, message: message)
    }

    private func finish(_ task: DownloadTask) {
        stopTiming(task)
        task.state = .completed
        task.speed = 0
        task.errorMessage = nil
        task.finishedAt = Date()
        if !task.segmentTotals.isEmpty {
            task.segmentBytes = task.segmentTotals
        } else if let total = task.totalBytes {
            task.segmentBytes = [total]
        }
        task.sessionTasks = [:]
        task.session?.finishTasksAndInvalidate()
        task.session = nil
        syncRecord(task)
        save()
        pump()
    }

    /// Failure keeps the part files so a retry resumes where it stopped.
    private func fail(_ task: DownloadTask, message: String) {
        stopTiming(task)
        task.state = .failed
        task.speed = 0
        task.errorMessage = message
        task.sessionTasks = [:]
        task.session?.invalidateAndCancel()
        task.session = nil
        syncRecord(task)
        save()
        pump()
    }

    private func stopTiming(_ task: DownloadTask) {
        let now = Date()
        for index in task.segmentActiveDates.indices {
            if let since = task.segmentActiveDates[index], task.segmentTimes.indices.contains(index) {
                task.segmentTimes[index] += now.timeIntervalSince(since)
                task.segmentActiveDates[index] = nil
            }
        }
    }

    // MARK: - Persistence

    private func syncRecord(_ task: DownloadTask) {
        let record = task.record
        record.state = task.state
        record.headers = task.headers
        record.totalBytes = task.totalBytes
        record.supportsRange = task.supportsRange
        record.segmentBytes = task.segmentBytes
        record.segmentTotals = task.segmentTotals
        record.segmentTimes = task.segmentTimes
        record.segmentRequestBases = task.segmentRequestBases
        record.segmentResumeBases = task.segmentResumeBases
        record.startedAt = task.startedAt
        record.finishedAt = task.finishedAt
        record.errorMessage = task.errorMessage
    }

    private func save() {
        try? context?.save()
    }

    // MARK: - Files

    private func downloadsDirectory() -> URL {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func destinationURL(of task: DownloadTask) -> URL {
        downloadsDirectory().appendingPathComponent(task.fileName)
    }

    private func uniqueFileName(for url: URL) -> String {
        let rawName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        return uniqueFileName(suggested: rawName.removingPercentEncoding ?? rawName)
    }

    func uniqueFileName(suggested name: String) -> String {
        let directory = downloadsDirectory()
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let reserved = Set(tasks.map(\.fileName))
        var candidate = name
        var index = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path)
                || reserved.contains(candidate) {
            candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            index += 1
        }
        return candidate
    }

    func destinationURL(forFileName fileName: String) -> URL {
        downloadsDirectory().appendingPathComponent(fileName)
    }

    /// Registers a file that was downloaded by the in-app browser itself
    /// (WKDownload path: POST or blob downloads we cannot replay).
    func registerCompletedDownload(fileName: String, sourceURL: URL?) {
        guard let context else { return }
        let fileURL = destinationURL(forFileName: fileName)
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let now = Date()
        let record = DownloadRecord(
            urlString: sourceURL?.absoluteString ?? "",
            fileName: fileName,
            state: .completed,
            totalBytes: size > 0 ? size : nil,
            requestedSegments: 1,
            segmentBytes: [size],
            segmentTotals: [size],
            startedAt: now,
            finishedAt: now
        )
        context.insert(record)
        save()
        tasks.insert(DownloadTask(record: record), at: 0)
    }

    private func partURL(of task: DownloadTask, segment: Int) -> URL {
        downloadsDirectory().appendingPathComponent(".\(task.id.uuidString).part\(segment)")
    }

    private func resumeDataURL(of task: DownloadTask, segment: Int) -> URL {
        downloadsDirectory().appendingPathComponent(".\(task.id.uuidString).part\(segment).resume")
    }

    private func cleanupParts(of task: DownloadTask) {
        for index in 0..<max(task.segmentBytes.count, task.requestedSegments) {
            try? FileManager.default.removeItem(at: partURL(of: task, segment: index))
            try? FileManager.default.removeItem(at: resumeDataURL(of: task, segment: index))
        }
    }

    // MARK: - Helpers

    private func isAlive(_ task: DownloadTask) -> Bool {
        task.state == .downloading && tasks.contains(where: { $0.id == task.id })
    }

    private func applyHeaders(of task: DownloadTask, to request: inout URLRequest) {
        for (field, value) in task.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private func setting(_ key: String, min lo: Int, max hi: Int, fallback: Int) -> Int {
        let value = UserDefaults.standard.object(forKey: key) as? Int ?? fallback
        return Swift.max(lo, Swift.min(hi, value))
    }
}

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    nonisolated private let taskID: UUID
    nonisolated private let manager: DownloadManager

    init(taskID: UUID, manager: DownloadManager) {
        self.taskID = taskID
        self.manager = manager
    }

    nonisolated private func segment(for task: URLSessionTask) -> Int {
        Int(task.taskDescription ?? "") ?? 0
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let segment = segment(for: downloadTask)
        let id = taskID
        let manager = self.manager
        Task { @MainActor in
            manager.task(
                id,
                segment: segment,
                didWriteBytes: bytesWritten,
                totalWritten: totalBytesWritten,
                expectedTotal: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let segment = segment(for: downloadTask)
        let id = taskID
        let manager = self.manager
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: staging)
        } catch {
            Task { @MainActor in
                manager.task(id, didFailWithError: error)
            }
            return
        }
        Task { @MainActor in
            manager.task(id, segment: segment, didFinishTo: staging)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }
        let id = taskID
        let manager = self.manager
        Task { @MainActor in
            manager.task(id, didFailWithError: error)
        }
    }
}
