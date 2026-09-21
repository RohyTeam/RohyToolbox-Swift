//
//  DownloadTaskDetailView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct DownloadTaskDetailView: View {
    let task: DownloadTask

    private var segmentCount: Int {
        max(task.segmentBytes.count, 1)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Link") {
                    Text(task.urlString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Started") {
                    dateText(task.startedAt)
                }
                LabeledContent("File Size") {
                    if let total = task.totalBytes {
                        Text(total.formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                if task.state == .completed {
                    LabeledContent("Finished") {
                        dateText(task.finishedAt)
                    }
                }
            }
            Section("Segments") {
                ForEach(0..<segmentCount, id: \.self) { index in
                    LabeledContent {
                        Text("\(segmentSizeString(index)) | \(segmentTimeString(index))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } label: {
                        Text("Segment #\(index + 1)")
                    }
                }
            }
        }
        .navigationTitle(task.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if task.state != .completed {
                DownloadManager.shared.popupTaskID = task.id
            }
        }
        .onChange(of: task.state) { _, newState in
            if newState == .completed, DownloadManager.shared.popupTaskID == task.id {
                DownloadManager.shared.popupTaskID = nil
            }
        }
        .onDisappear {
            if DownloadManager.shared.popupTaskID == task.id {
                DownloadManager.shared.popupTaskID = nil
            }
        }
    }

    private func dateText(_ date: Date?) -> Text {
        if let date {
            return Text(date, format: .dateTime)
                .foregroundStyle(.secondary)
        }
        return Text("—")
            .foregroundStyle(.secondary)
    }

    private func segmentSizeString(_ index: Int) -> String {
        let bytes = task.segmentBytes.indices.contains(index) ? task.segmentBytes[index] : 0
        return bytes.formatted(.byteCount(style: .file))
    }

    private func segmentTimeString(_ index: Int) -> String {
        let time = task.segmentTimes.indices.contains(index) ? task.segmentTimes[index] : 0
        return Self.formatDuration(time)
    }

    static func formatDuration(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// A progress bar split into one segment per download part.
struct DownloadSegmentBar: View {
    let task: DownloadTask

    private var fractions: [Double] {
        if task.isSegmented {
            return task.segmentBytes.indices.map { index in
                let total = task.segmentTotals.indices.contains(index) ? task.segmentTotals[index] : 0
                return total > 0 ? Double(task.segmentBytes[index]) / Double(total) : 0
            }
        }
        guard let total = task.totalBytes, total > 0 else { return [0] }
        return [Double(task.downloadedBytes) / Double(total)]
    }

    var body: some View {
        if task.totalBytes == nil {
            ProgressView()
                .progressViewStyle(.linear)
        } else {
            HStack(spacing: 2) {
                ForEach(fractions.indices, id: \.self) { index in
                    SegmentFill(fraction: fractions[index])
                }
            }
        }
    }
}

private struct SegmentFill: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

/// The custom LNPopupUI bar shown while the detail page is open.
/// Tapping anywhere on the bar toggles pause / resume.
struct DownloadPopupBar: View {
    let task: DownloadTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.state == .downloading ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                DownloadSegmentBar(task: task)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            DownloadManager.shared.toggle(task)
        }
    }
}

#Preview {
    NavigationStack {
        DownloadTaskDetailView(task: DownloadTask(record: DownloadRecord(
            urlString: "https://example.com/file.zip",
            fileName: "file.zip",
            requestedSegments: 4,
            segmentBytes: [12_000_000, 8_000_000],
            segmentTotals: [25_000_000, 25_000_000],
            segmentTimes: [120, 95]
        )))
    }
}
