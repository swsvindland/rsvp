//
//  ContentView.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Compression

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.createdAt) private var books: [Book]

    @State private var selectedTab: Int = 0

    // Reader state
    @State private var words: [String] = []
    @State private var currentIndex: Int = 0
    @State private var isPressing: Bool = false
    @State private var wpm: Double = 400 // default speed
    @State private var advanceTask: Task<Void, Never>? = nil

    // Books state
    @State private var isShowingAddBook: Bool = false

    private var interval: TimeInterval { max(0.03, 60.0 / max(wpm, 1)) }

    private var activeBook: Book? {
        books.first(where: { $0.isActive })
    }

    // Compute Optimal Recognition Point (ORP) index based on word length
    private func orpIndex(for word: String) -> Int {
        // Simple heuristic similar to common RSVP implementations
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
        // Keep trailing punctuation separate so ORP stays on the core word
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
        // Append punctuation back (uncolored)
        if !trailingPunctuation.isEmpty {
            let punct = AttributedString(trailingPunctuation)
            attr.append(punct)
        }
        return attr
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Read Tab
            NavigationStack {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isPressing {
                                        isPressing = true
                                    }
                                }
                                .onEnded { _ in
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

                        VStack(spacing: 12) {
                            HStack {
                                Text("WPM: \(Int(wpm))")
                                Slider(value: $wpm, in: 100...900, step: 10)
                            }
                            HStack {
                                Button("Reset") {
                                    currentIndex = 0
                                }
                                .buttonStyle(.bordered)
                                .disabled(words.isEmpty)

                                Spacer()

                                Text("\(min(currentIndex + 1, max(words.count, 1)))/\(max(words.count, 1))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
                .navigationTitle("Read")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Books") {
                            selectedTab = 1
                        }
                    }
                }
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
                    if newValue {
                        // Start a new advancing task if none is running
                        if advanceTask == nil {
                            advanceTask = Task { @MainActor in
                                while !Task.isCancelled && isPressing {
                                    if currentIndex + 1 < words.count {
                                        currentIndex += 1
                                    }
                                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                                }
                                advanceTask = nil
                            }
                        }
                    } else {
                        // Stop the advancing task immediately
                        advanceTask?.cancel()
                        advanceTask = nil
                    }
                }
            }
            .tabItem {
                Label("Read", systemImage: "book")
            }
            .tag(0)

            // Books Tab
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
            .tabItem {
                Label("Books", systemImage: "books.vertical")
            }
            .tag(1)

            // Settings Tab
            NavigationStack {
                Form {
                    Section(header: Text("General")) {
                        Toggle("Example Setting", isOn: .constant(true))
                        Toggle("Another Setting", isOn: .constant(false))
                    }
                }
                .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
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
        loadActiveBook()
    }

    private func deleteBooks(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(books[index])
            }
        }
        loadActiveBook()
    }
}

struct BookDraft {
    var title: String = ""
    var sourceType: BookSourceType = .text
    var text: String = ""
    var epubFileName: String?
    var epubFilePath: String?
    var isActive: Bool = false
}

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

private func storeEpub(from url: URL) throws -> (fileName: String, filePath: String, extractedText: String) {
    let fileManager = FileManager.default
    let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    guard let documents else {
        throw NSError(domain: "rsvp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents folder."])
    }

    let baseName = url.deletingPathExtension().lastPathComponent
    let fileExtension = url.pathExtension.isEmpty ? "epub" : url.pathExtension
    var destination = documents.appendingPathComponent("\(baseName).\(fileExtension)")
    var counter = 1
    while fileManager.fileExists(atPath: destination.path) {
        destination = documents.appendingPathComponent("\(baseName)-\(counter).\(fileExtension)")
        counter += 1
    }

    if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
    }

    try fileManager.copyItem(at: url, to: destination)

    let extractedText = try extractEpubText(from: destination)
    return (destination.lastPathComponent, destination.path, extractedText)
}

private func extractEpubText(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let archive = try ZipArchive(data: data)

    let containerPath = "META-INF/container.xml"
    guard let containerData = try archive.data(for: containerPath) else {
        throw EpubExtractionError.missingContainer
    }

    let containerParser = EpubContainerParser()
    let containerXML = XMLParser(data: containerData)
    containerXML.delegate = containerParser
    containerXML.parse()

    guard let rootFilePath = containerParser.rootFilePath else {
        throw EpubExtractionError.missingRootFile
    }

    let opfPath = rootFilePath
    let opfData = try archive.data(for: opfPath)
    guard let opfData else {
        throw EpubExtractionError.missingOpf
    }

    let opfParser = EpubOpfParser()
    let opfXML = XMLParser(data: opfData)
    opfXML.delegate = opfParser
    opfXML.parse()

    let basePath = (opfPath as NSString).deletingLastPathComponent
    let spinePaths = opfParser.spineItemRefs.compactMap { idref -> String? in
        guard let href = opfParser.manifest[idref] else { return nil }
        return basePath.isEmpty ? href : "\(basePath)/\(href)"
    }

    let candidatePaths: [String]
    if !spinePaths.isEmpty {
        candidatePaths = spinePaths
    } else {
        candidatePaths = archive.entries
            .filter { $0.name.lowercased().hasSuffix(".xhtml") || $0.name.lowercased().hasSuffix(".html") || $0.name.lowercased().hasSuffix(".htm") }
            .map { $0.name }
            .sorted()
    }

    if candidatePaths.isEmpty {
        throw EpubExtractionError.missingContent
    }

    var combinedText: [String] = []
    for path in candidatePaths {
        guard let htmlData = try archive.data(for: path) else { continue }
        guard let htmlString = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .isoLatin1) else {
            continue
        }
        let text = plainText(from: htmlString)
        if !text.isEmpty {
            combinedText.append(text)
        }
    }

    let result = combinedText.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if result.isEmpty {
        throw EpubExtractionError.emptyText
    }
    return result
}

private func plainText(from html: String) -> String {
    var output = html
    output = output.replacingOccurrences(of: "(?is)<script.*?>.*?</script>", with: " ", options: .regularExpression)
    output = output.replacingOccurrences(of: "(?is)<style.*?>.*?</style>", with: " ", options: .regularExpression)
    output = output.replacingOccurrences(of: "(?is)<head.*?>.*?</head>", with: " ", options: .regularExpression)
    output = output.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    output = output.replacingOccurrences(of: "&nbsp;", with: " ")
    output = output.replacingOccurrences(of: "&amp;", with: "&")
    output = output.replacingOccurrences(of: "&lt;", with: "<")
    output = output.replacingOccurrences(of: "&gt;", with: ">")
    output = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private enum EpubExtractionError: LocalizedError {
    case missingContainer
    case missingRootFile
    case missingOpf
    case missingContent
    case emptyText
    case invalidZip
    case unsupportedCompression
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            return "The EPUB is missing META-INF/container.xml."
        case .missingRootFile:
            return "The EPUB container did not specify a root file."
        case .missingOpf:
            return "The EPUB package file could not be read."
        case .missingContent:
            return "The EPUB did not contain readable HTML content."
        case .emptyText:
            return "The EPUB content could not be converted to text."
        case .invalidZip:
            return "The EPUB archive appears to be invalid."
        case .unsupportedCompression:
            return "The EPUB uses a compression method that is not supported yet."
        case .decompressionFailed:
            return "The EPUB contents could not be decompressed."
        }
    }
}

private struct ZipEntry {
    let name: String
    let compressionMethod: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

private struct ZipArchive {
    let data: Data
    let entries: [ZipEntry]

    init(data: Data) throws {
        self.data = data
        self.entries = try ZipArchive.readEntries(from: data)
    }

    func data(for path: String) throws -> Data? {
        guard let entry = entries.first(where: { $0.name == path }) else { return nil }
        return try extract(entry)
    }

    private func extract(_ entry: ZipEntry) throws -> Data {
        let localOffset = Int(entry.localHeaderOffset)
        guard localOffset + 30 <= data.count else { throw EpubExtractionError.invalidZip }

        let signature = ZipArchive.readUInt32(data, offset: localOffset)
        guard signature == 0x04034b50 else { throw EpubExtractionError.invalidZip }

        let nameLength = Int(ZipArchive.readUInt16(data, offset: localOffset + 26))
        let extraLength = Int(ZipArchive.readUInt16(data, offset: localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        let dataEnd = dataStart + Int(entry.compressedSize)
        guard dataEnd <= data.count else { throw EpubExtractionError.invalidZip }

        let compressedData = data.subdata(in: dataStart..<dataEnd)
        switch entry.compressionMethod {
        case 0:
            return compressedData
        case 8:
            return try inflate(compressedData)
        default:
            throw EpubExtractionError.unsupportedCompression
        }
    }

    private func inflate(_ compressed: Data) throws -> Data {
        let dstPlaceholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let srcPlaceholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer {
            dstPlaceholder.deallocate()
            srcPlaceholder.deallocate()
        }

        var stream = compression_stream(
            dst_ptr: dstPlaceholder,
            dst_size: 0,
            src_ptr: UnsafePointer(srcPlaceholder),
            src_size: 0,
            state: nil
        )
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw EpubExtractionError.decompressionFailed
        }
        defer { compression_stream_destroy(&stream) }

        let dstBufferSize = 64 * 1024
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
        defer { dstBuffer.deallocate() }

        var output = Data()
        return try compressed.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw EpubExtractionError.decompressionFailed
            }

            stream.src_ptr = baseAddress
            stream.src_size = compressed.count

            while true {
                stream.dst_ptr = dstBuffer
                stream.dst_size = dstBufferSize

                status = compression_stream_process(&stream, 0)
                let written = dstBufferSize - stream.dst_size
                if written > 0 {
                    output.append(dstBuffer, count: written)
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    throw EpubExtractionError.decompressionFailed
                }
            }
        }
    }

    private static func readEntries(from data: Data) throws -> [ZipEntry] {
        let eocdOffset = try findEndOfCentralDirectory(in: data)
        let centralDirectoryOffset = Int(readUInt32(data, offset: eocdOffset + 16))
        let centralDirectorySize = Int(readUInt32(data, offset: eocdOffset + 12))

        guard centralDirectoryOffset + centralDirectorySize <= data.count else {
            throw EpubExtractionError.invalidZip
        }

        var entries: [ZipEntry] = []
        var cursor = centralDirectoryOffset
        let end = centralDirectoryOffset + centralDirectorySize

        while cursor + 46 <= end {
            let signature = readUInt32(data, offset: cursor)
            guard signature == 0x02014b50 else { break }

            let compressionMethod = readUInt16(data, offset: cursor + 10)
            let compressedSize = readUInt32(data, offset: cursor + 20)
            let uncompressedSize = readUInt32(data, offset: cursor + 24)
            let nameLength = Int(readUInt16(data, offset: cursor + 28))
            let extraLength = Int(readUInt16(data, offset: cursor + 30))
            let commentLength = Int(readUInt16(data, offset: cursor + 32))
            let localHeaderOffset = readUInt32(data, offset: cursor + 42)

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else { throw EpubExtractionError.invalidZip }

            let nameData = data.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""

            entries.append(
                ZipEntry(
                    name: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )

            cursor = nameEnd + extraLength + commentLength
        }

        if entries.isEmpty {
            throw EpubExtractionError.invalidZip
        }
        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        let signature: UInt32 = 0x06054b50
        let minOffset = max(0, data.count - 65_557)
        var offset = data.count - 22

        while offset >= minOffset {
            if readUInt32(data, offset: offset) == signature {
                return offset
            }
            offset -= 1
        }

        throw EpubExtractionError.invalidZip
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        let value = data.withUnsafeBytes { rawBuffer -> UInt16 in
            let pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return UInt16(pointer[offset]) | (UInt16(pointer[offset + 1]) << 8)
        }
        return value
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        let value = data.withUnsafeBytes { rawBuffer -> UInt32 in
            let pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            return UInt32(pointer[offset])
                | (UInt32(pointer[offset + 1]) << 8)
                | (UInt32(pointer[offset + 2]) << 16)
                | (UInt32(pointer[offset + 3]) << 24)
        }
        return value
    }
}

private final class EpubContainerParser: NSObject, XMLParserDelegate {
    private(set) var rootFilePath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        if elementName == "rootfile", let fullPath = attributeDict["full-path"] {
            rootFilePath = fullPath
        }
    }
}

private final class EpubOpfParser: NSObject, XMLParserDelegate {
    private(set) var manifest: [String: String] = [:]
    private(set) var spineItemRefs: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest[id] = href
        } else if elementName == "itemref", let idref = attributeDict["idref"] {
            spineItemRefs.append(idref)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
