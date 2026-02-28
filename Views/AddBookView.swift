//
//  AddBookView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: BookDraft = BookDraft()
    @State private var isImportingEpub: Bool = false
    @State private var importErrorMessage: String = ""
    @State private var isShowingImportError: Bool = false

    let onSave: (BookDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Title", text: $draft.title)
                    Picker("Source", selection: $draft.sourceType) {
                        ForEach(BookSourceType.allCases) { sourceType in
                            Text(sourceType.displayName).tag(sourceType)
                        }
                    }
                    Toggle("Set as active", isOn: $draft.isActive)
                }

                if draft.sourceType == .text {
                    Section(header: Text("Text")) {
                        TextEditor(text: $draft.text)
                            .frame(minHeight: 200)
                    }
                } else {
                    Section(header: Text("EPUB")) {
                        if let epubFileName = draft.epubFileName {
                            Text(epubFileName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No EPUB selected")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button("Import EPUB") {
                            isImportingEpub = true
                        }
                    }
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $isImportingEpub,
                allowedContentTypes: [UTType.epub]
            ) { result in
                switch result {
                case .success(let url):
                    do {
                        let stored = try storeEpub(from: url)
                        draft.epubFileName = stored.fileName
                        draft.epubFilePath = stored.filePath
                        draft.text = stored.extractedText
                        draft.sourceType = .epub
                    } catch {
                        importErrorMessage = error.localizedDescription
                        isShowingImportError = true
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    isShowingImportError = true
                }
            }
            .alert("EPUB Import Failed", isPresented: $isShowingImportError) {
                Button("OK") { }
            } message: {
                Text(importErrorMessage)
            }
        }
    }
}
