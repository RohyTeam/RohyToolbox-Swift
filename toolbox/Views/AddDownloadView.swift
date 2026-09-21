//
//  AddDownloadView.swift
//  toolbox
//
//  Created by Deerio on 2026/9/18.
//

import SwiftUI

struct AddDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var customName = ""
    @State private var headers: [HeaderEntry] = []

    private struct HeaderEntry: Identifiable {
        let id = UUID()
        var key = ""
        var value = ""
    }

    private var url: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    private var headerDictionary: [String: String] {
        var result: [String: String] = [:]
        for entry in headers {
            let key = entry.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                result[key] = entry.value.trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("File Name (Optional)", text: $customName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if headers.isEmpty {
                    Section {
                        Button {
                            headers.append(HeaderEntry())
                        } label: {
                            Label("Add Header", systemImage: "plus")
                        }
                    }
                } else {
                    Section {
                        ForEach($headers) { $entry in
                            HStack(spacing: 12) {
                                TextField("Header Key", text: $entry.key)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                TextField("Header Value", text: $entry.value)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                        .onDelete { offsets in
                            headers.remove(atOffsets: offsets)
                        }
                    } header: {
                        HStack {
                            Text("Headers")
                            Spacer()
                            Button {
                                headers.append(HeaderEntry())
                            } label: {
                                Label("Add Header", systemImage: "plus")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let url {
                            DownloadManager.shared.add(
                                url: url,
                                headers: headerDictionary,
                                fileName: customName
                            )
                        }
                        dismiss()
                    }
                    .disabled(url == nil)
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    AddDownloadView()
}
