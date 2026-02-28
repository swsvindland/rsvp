//
//  BookEditorView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BookEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: Book

    @State private var isImportingEpub: Bool = false
    @State private var importErrorMessage: String = ""
    @State private var isShowingImportError: Bool = false

    let onSetActive: () -> Void

    var body: some View {
        Form {
            Section(header: Text("Details")) {
                TextField("Title", text: $book.title)
                Picker("Source", selection: $book.sourceType) {
                    ForEach(BookSourceType.allCases) { sourceType in
                        Text(sourceType.displayName).tag(sourceType)
                    }
                }
                Button("Set as Active") {
                    onSetActive()
                    dismiss()
                }
            }

            if book.sourceType == .text {
                Section(header: Text("Text")) {
                    TextEditor(text: $book.text)
                        .frame(minHeight: 200)
                }
            } else {
                Section(header: Text("EPUB")) {
                    if let epubFileName = book.epubFileName {
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
        .navigationTitle(book.title.isEmpty ? "Edit Book" : book.title)
        .fileImporter(
            isPresented: $isImportingEpub,
            allowedContentTypes: [UTType.epub]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let stored = try storeEpub(from: url)
                    book.epubFileName = stored.fileName
                    book.epubFilePath = stored.filePath
                    book.text = stored.extractedText
                    book.sourceType = .epub
                    book.updatedAt = Date()
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
