//
//  SwiftStoreAppDetailView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct SwiftStoreAppDetailView: View {
    let app: StoreApp

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
            Section("Versions") {
                ForEach(app.versions, id: \.name) { version in
                    StoreVersionRow(version: version)
                }
            }
            ForEach(app.sources) { source in
                Section(source.name) {
                    ForEach(source.versions, id: \.name) { version in
                        StoreVersionRow(version: version)
                    }
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
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
            versions: [
                StoreVersion(
                    name: "v1.0.0",
                    size: 3548580,
                    createdAt: .now.addingTimeInterval(-90),
                    url: URL(string: "https://example.com/lanlu.ipa")!
                )
            ]
        ))
    }
}
