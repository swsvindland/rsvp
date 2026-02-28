//
//  BooksTabView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI
import SwiftData

struct BooksTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.createdAt) private var books: [Book]

    @State private var isShowingAddBook: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if books.isEmpty {
                    ContentUnavailableView("No books yet", systemImage: "books.vertical")
                } else {
                    ForEach(books) { book in
                        NavigationLink {
                            BookEditorView(book: book, onSetActive: {
                                setActiveBook(book)
                            })
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title.isEmpty ? "Untitled" : book.title)
                                        .fontWeight(.semibold)
                                    Text(book.sourceType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if !book.text.isEmpty {
                                    Text("\(Int(book.progress * 100))%")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(book.sourceType == .epub ? "EPUB" : "Empty")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if book.isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                setActiveBook(book)
                            } label: {
                                Label("Set Active", systemImage: "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteBooks)
                }
            }
            .navigationTitle("Books")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddBook = true
                    } label: {
                        Label("Add Book", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddBook) {
                AddBookView { draft in
                    addBook(from: draft)
                }
            }
        }
    }

    private func addBook(from draft: BookDraft) {
        withAnimation {
            let newBook = Book(
                title: draft.title,
                sourceType: draft.sourceType,
                text: draft.text,
                epubFileName: draft.epubFileName,
                epubFilePath: draft.epubFilePath,
                isActive: draft.isActive
            )
            modelContext.insert(newBook)
            if draft.isActive {
                setActiveBook(newBook)
            }
        }
    }

    private func setActiveBook(_ book: Book) {
        withAnimation {
            for existing in books {
                existing.isActive = existing.persistentModelID == book.persistentModelID
            }
        }
    }

    private func deleteBooks(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(books[index])
            }
        }
    }
}
