//
//  SwiftStoreAppDetailView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct SwiftStoreAppDetailView: View {
    let app: StoreApp

    @State private var detail: StoreAppDetail?
    @State private var loadFailed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("ID", value: app.id)
                LabeledContent("Name", value: app.name)
                LabeledContent("Authors", value: app.authors.joined(separator: ", "))
                LabeledContent("AI-Assisted", value: app.aiAssisted
                    ? String(localized: "Yes")
                    : String(localized: "No"))
                LabeledContent("Repository") {
                    Text(app.repo.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let detail {
                Section("Versions") {
                    ForEach(detail.versions, id: \.name) { version in
                        StoreVersionRow(version: version)
                    }
                }
                ForEach(detail.sources) { source in
                    Section(source.name) {
                        ForEach(source.versions ?? [], id: \.name) { version in
                            StoreVersionRow(version: version)
                        }
                    }
                }
            } else {
                Section {
                    if loadFailed {
                        Button {
                            load()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        loadFailed = false
        Task {
            do {
                detail = try await SwiftStore.shared.detail(for: app)
            } catch {
                loadFailed = true
            }
        }
    }
}

private struct StoreVersionRow: View {
    let version: StoreVersion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(version.name)
                    if version.prerelease {
                        Text("beta")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.yellow, in: .capsule)
                    }
                }
                Text(RelativeTime.string(from: version.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DownloadCapsuleButton(version: version)
        }
    }
}

#Preview {
    NavigationStack {
        SwiftStoreAppDetailView(app: StoreApp(
            id: "lanlu",
            name: "lanlu-iOS",
            description: "lanlu client for iOS",
            authors: ["copurx", "DeeChael"],
            aiAssisted: true,
            repo: URL(string: "https://github.com/DeeChael/lanlu-iOS")!,
            latestVersion: "v1.0.0",
            latestReleaseVersion: "v1.0.0"
        ))
    }
}
