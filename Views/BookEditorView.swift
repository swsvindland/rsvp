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
    @Environment(\.modelContext) private var modelContext
    @Bindable var book: Book

    @State private var isImportingEpub: Bool = false
    @State private var importErrorMessage: String = ""
    @State private var isShowingImportError: Bool = false
    @State private var isShowingRestartConfirmation: Bool = false
    @State private var isShowingDeleteConfirmation: Bool = false

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
                Button("Restart Book", role: .destructive) {
                    isShowingRestartConfirmation = true
                }
                Button("Delete Book", role: .destructive) {
                    isShowingDeleteConfirmation = true
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
        .confirmationDialog(
            "Restart this book from the beginning?",
            isPresented: $isShowingRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restart Book", role: .destructive) {
                restartBook()
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Delete this book? This cannot be undone.",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Book", role: .destructive) {
                deleteBook()
            }
            Button("Cancel", role: .cancel) { }
        }
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

    private func restartBook() {
        withAnimation {
            book.currentWordIndex = 0
            book.progress = 0
            book.updatedAt = Date()
        }
    }

    private func deleteBook() {
        withAnimation {
            modelContext.delete(book)
            dismiss()
        }
    }
}
