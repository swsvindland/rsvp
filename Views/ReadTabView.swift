//
//  ReadTabView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI
import SwiftData

struct ReadTabView: View {
    @Query(sort: \Book.createdAt) private var books: [Book]

    @AppStorage("wpm") private var wpm: Double = 400
    @AppStorage("holdToPlay") private var holdToPlay: Bool = true

    @State private var words: [String] = []
    @State private var currentIndex: Int = 0
    @State private var isPressing: Bool = false
    @State private var isPlaying: Bool = false
    @State private var advanceTask: Task<Void, Never>? = nil

    private var interval: TimeInterval { max(0.03, 60.0 / max(wpm, 1)) }

    private var activeBook: Book? {
        books.first(where: { $0.isActive })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard holdToPlay else { return }
                                if !isPressing { isPressing = true }
                            }
                            .onEnded { _ in
                                guard holdToPlay else { return }
                                isPressing = false
                            }
                    )

                VStack(spacing: 24) {
                    Spacer()
                    if let book = activeBook {
                        if words.indices.contains(currentIndex) {
                            Text(styledWord(words[currentIndex]))
                                .font(.system(size: 48, weight: .semibold, design: .rounded))
                                .minimumScaleFactor(0.3)
                                .lineLimit(1)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .animation(.easeInOut(duration: 0.08), value: currentIndex)
                        } else if words.isEmpty {
                            VStack(spacing: 12) {
                                Text("No readable text")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text(book.sourceType == .epub
                                     ? "This EPUB didn’t provide readable text. Try another file or re-import."
                                     : "Add text to this book in the Books tab to start reading.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal)
                        } else {
                            Text("")
                                .font(.system(size: 48, weight: .semibold, design: .rounded))
                                .minimumScaleFactor(0.3)
                                .lineLimit(1)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .animation(.easeInOut(duration: 0.08), value: currentIndex)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text("No active book")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Pick a book in the Books tab to start reading.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 16) {
                        if !holdToPlay {
                            Button {
                                isPlaying.toggle()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Circle().fill(.blue))
                            }
                            .buttonStyle(.plain)
                            .disabled(words.isEmpty)
                            .opacity(words.isEmpty ? 0.5 : 1)
                        }

                        Text("\(min(currentIndex + 1, max(words.count, 1)))/\(max(words.count, 1))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Read")
            .onAppear {
                loadActiveBook()
            }
            .onChange(of: activeBook?.persistentModelID) { _, _ in
                loadActiveBook()
            }
            .onChange(of: activeBook?.text) { _, _ in
                loadActiveBook()
            }
            .onChange(of: activeBook?.sourceType) { _, _ in
                loadActiveBook()
            }
            .onChange(of: currentIndex) { _, _ in
                persistProgressIfNeeded()
            }
            .onChange(of: isPressing) { _, newValue in
                guard holdToPlay else { return }
                updateAdvanceTask()
            }
            .onChange(of: isPlaying) { _, _ in
                guard !holdToPlay else { return }
                updateAdvanceTask()
            }
            .onChange(of: holdToPlay) { _, newValue in
                if newValue {
                    isPlaying = false
                } else {
                    isPressing = false
                }
                updateAdvanceTask()
            }
        }
    }

    private func loadActiveBook() {
        guard let book = activeBook else {
            words = []
            currentIndex = 0
            return
        }

        words = makeWords(from: book.text)
        if words.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(book.currentWordIndex, max(words.count - 1, 0))
        }
    }

    private func makeWords(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private func persistProgressIfNeeded() {
        guard let book = activeBook else { return }
        if words.isEmpty {
            book.currentWordIndex = 0
            book.progress = 0
            book.updatedAt = Date()
            return
        }

        book.currentWordIndex = min(currentIndex, max(words.count - 1, 0))
        book.progress = Double(book.currentWordIndex + 1) / Double(words.count)
        book.updatedAt = Date()
    }

    private func updateAdvanceTask() {
        let shouldAdvance = holdToPlay ? isPressing : isPlaying
        if shouldAdvance {
            if advanceTask == nil {
                advanceTask = Task { @MainActor in
                    while !Task.isCancelled && (holdToPlay ? isPressing : isPlaying) {
                        if currentIndex + 1 < words.count {
                            currentIndex += 1
                        }
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                    advanceTask = nil
                }
            }
        } else {
            advanceTask?.cancel()
            advanceTask = nil
        }
    }

    private func orpIndex(for word: String) -> Int {
        let count = word.count
        switch count {
        case 0: return 0
        case 1...2: return 0
        case 3...5: return 1
        case 6...9: return 2
        default: return 3
        }
    }

    private func styledWord(_ word: String) -> AttributedString {
        var stripped = word
        let punctuationSet = CharacterSet.punctuationCharacters
        var trailingPunctuation = ""
        while let last = stripped.unicodeScalars.last, punctuationSet.contains(last) {
            trailingPunctuation = String(stripped.removeLast()) + trailingPunctuation
        }

        var attr = AttributedString(stripped)
        let idx = orpIndex(for: stripped)
        if idx < stripped.count, let range = Range(NSRange(location: idx, length: 1), in: String(stripped)) {
            let start = AttributedString.Index(range.lowerBound, within: attr) ?? attr.startIndex
            let end = AttributedString.Index(range.upperBound, within: attr) ?? attr.endIndex
            if start < end { attr[start..<end].foregroundColor = .red }
        }
        if !trailingPunctuation.isEmpty {
            let punct = AttributedString(trailingPunctuation)
            attr.append(punct)
        }
        return attr
    }
}
