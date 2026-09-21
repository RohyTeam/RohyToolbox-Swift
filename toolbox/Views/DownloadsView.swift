//
//  DownloadsView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct DownloadsView: View {
    @State private var manager = DownloadManager.shared
    @State private var showsAddSheet = false
    @State private var showsWebSheet = false
    @State private var selectedTask: DownloadTask?
    @State private var completedTaskPendingDeletion: DownloadTask?

    var body: some View {
        NavigationStack {
            List {
                if !manager.activeTasks.isEmpty {
                    Section("Downloading") {
                        ForEach(manager.activeTasks) { task in
                            activeRow(for: task)
                        }
                    }
                }
                if !manager.completedTasks.isEmpty {
                    Section("Completed") {
                        ForEach(manager.completedTasks) { task in
                            completedRow(for: task)
                        }
                    }
                }
            }
            .overlay {
                if manager.tasks.isEmpty {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Files you download will appear here.")
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationDestination(item: $selectedTask) { task in
                DownloadTaskDetailView(task: task)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        manager.pauseAll()
                    } label: {
                        Label("Pause All", systemImage: "pause.fill")
                    }
                    .disabled(!manager.hasDownloadingTasks)
                    Button {
                        manager.resumeAllPaused()
                    } label: {
                        Label("Resume All", systemImage: "play.fill")
                    }
                    .disabled(!manager.hasPausedTasks)
                    Menu {
                        Button {
                            showsAddSheet = true
                        } label: {
                            Label("URL", systemImage: "link")
                        }
                        Button {
                            showsWebSheet = true
                        } label: {
                            Label("Browse Web", systemImage: "safari")
                        }
                    } label: {
                        Label("Add Download", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsAddSheet) {
                AddDownloadView()
            }
            .sheet(isPresented: $showsWebSheet) {
                WebDownloadView()
            }
            .confirmationDialog(
                "Delete Download",
                isPresented: Binding(
                    get: { completedTaskPendingDeletion != nil },
                    set: { if !$0 { completedTaskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Local File Too", role: .destructive) {
                    if let task = completedTaskPendingDeletion {
                        manager.delete(task, removeFile: true)
                    }
                }
                Button("Delete Record Only") {
                    if let task = completedTaskPendingDeletion {
                        manager.delete(task, removeFile: false)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func activeRow(for task: DownloadTask) -> some View {
        DownloadTaskRow(task: task) {
            selectedTask = task
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                // Also removes any partially downloaded data.
                manager.delete(task, removeFile: true)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
        }
        .swipeActions(edge: .leading) {
            if task.state == .failed {
                Button {
                    manager.retry(task)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .tint(.orange)
            }
        }
    }

    private func completedRow(for task: DownloadTask) -> some View {
        CompletedTaskRow(task: task)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTask = task
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    completedTaskPendingDeletion = task
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
            }
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTask
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.fileName)
                    .font(.headline)
                    .lineLimit(1)

                switch task.state {
                case .waiting:
                    Text("Waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed:
                    Text(task.errorMessage ?? String(localized: "Failed"))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                case .downloading:
                    DownloadSegmentBar(task: task)
                        .frame(height: 5)
                    HStack {
                        Text(Int64(task.speed).formatted(.byteCount(style: .file)) + "/s")
                        Spacer()
                        sizeText
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                case .paused:
                    DownloadSegmentBar(task: task)
                        .frame(height: 5)
                    HStack {
                        Text("Paused")
                        Spacer()
                        sizeText
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                case .completed:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            controlButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var controlButton: some View {
        switch task.state {
        case .downloading:
            Button {
                DownloadManager.shared.pause(task)
            } label: {
                Label("Pause", systemImage: "pause.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.title2)
        case .paused:
            Button {
                DownloadManager.shared.resume(task)
            } label: {
                Label("Resume", systemImage: "play.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.title2)
        case .waiting:
            Button {
                DownloadManager.shared.startNow(task)
            } label: {
                Label("Start Now", systemImage: "bolt.circle.fill")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.title2)
        case .failed, .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var sizeText: some View {
        let downloaded = task.downloadedBytes.formatted(.byteCount(style: .file))
        if let total = task.totalBytes {
            Text("\(downloaded) / \(total.formatted(.byteCount(style: .file)))")
        } else {
            Text(downloaded)
        }
    }
}

private struct CompletedTaskRow: View {
    let task: DownloadTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName)
                    .font(.headline)
                    .lineLimit(1)
                if let total = task.totalBytes {
                    Text(total.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DownloadsView()
}
