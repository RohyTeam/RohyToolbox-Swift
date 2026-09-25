//
//  SwiftStoreView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct SwiftStoreView: View {
    @State private var store = SwiftStore.shared
    @State private var selectedApp: StoreApp?

    var body: some View {
        NavigationStack {
            List(store.apps) { app in
                StoreAppRow(app: app) {
                    selectedApp = app
                }
            }
            .navigationTitle("Swift Store")
            .navigationDestination(item: $selectedApp) { app in
                SwiftStoreAppDetailView(app: app)
            }
            .refreshable {
                await store.refresh()
            }
            .overlay {
                if store.apps.isEmpty {
                    if store.isLoading {
                        ProgressView()
                    } else if store.loadFailed {
                        ContentUnavailableView {
                            Label("Couldn't Load", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("Check your connection and pull to retry.")
                        }
                    }
                }
            }
            .task {
                store.load()
            }
        }
    }
}

private struct StoreAppRow: View {
    let app: StoreApp
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            StoreAppIcon(app: app)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(app.name)
                        .font(.body)
                        .lineLimit(1)
                    Text(app.listedVersionName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(app.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            StoreDownloadButton(app: app)
        }
        .padding(.vertical, 4)
    }
}

struct StoreAppIcon: View {
    let app: StoreApp
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    private var url: URL? {
        app.iconURL(dark: colorScheme == .dark)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Hairline border so white icons don't blend into the background.
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .task(id: url) {
            image = await AppIconCache.shared.image(for: url)
        }
    }
}

/// The capsule "Download" button used in the detail page's version rows.
struct DownloadCapsuleButton: View {
    let version: StoreVersion

    var body: some View {
        Button {
            DownloadManager.shared.add(url: SwiftStore.applyMirror(to: version.url))
        } label: {
            Text("Download")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

/// The capsule "Download" button in the list: the version URL is resolved
/// from the API first (apps.json carries no download URLs).
struct StoreDownloadButton: View {
    let app: StoreApp
    @State private var fetching = false

    var body: some View {
        Button {
            fetching = true
            Task {
                defer { fetching = false }
                if let url = try? await SwiftStore.shared.downloadURL(for: app) {
                    DownloadManager.shared.add(url: SwiftStore.applyMirror(to: url))
                }
            }
        } label: {
            Text("Download")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(fetching)
    }
}

#Preview {
    SwiftStoreView()
}
