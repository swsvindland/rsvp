//
//  EpubImporting.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import Foundation
import Compression

func storeEpub(from url: URL) throws -> (fileName: String, filePath: String, extractedText: String) {
    let fileManager = FileManager.default
    let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    guard let documents else {
        throw NSError(domain: "rsvp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents folder."])
    }

    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    if fileManager.isUbiquitousItem(at: url) {
        try? fileManager.startDownloadingUbiquitousItem(at: url)
    }

    let baseName = url.deletingPathExtension().lastPathComponent
    let fileExtension = url.pathExtension.isEmpty ? "epub" : url.pathExtension
    var destination = documents.appendingPathComponent("\(baseName).\(fileExtension)")
    var counter = 1
    while fileManager.fileExists(atPath: destination.path) {
        destination = documents.appendingPathComponent("\(baseName)-\(counter).\(fileExtension)")
        counter += 1
    }

    var storedResult: (fileName: String, filePath: String, extractedText: String)?
    var storedError: Error?
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            try fileManager.copyItem(at: readURL, to: destination)
            let extractedText = try extractEpubText(from: destination)
            storedResult = (destination.lastPathComponent, destination.path, extractedText)
        } catch {
            storedError = error
        }
    }

    if let coordinationError {
        throw coordinationError
    }
    if let storedError {
        throw storedError
    }
    guard let storedResult else {
        throw NSError(domain: "rsvp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to import the EPUB."])
    }

    return storedResult
}

func extractEpubText(from url: URL) throws -> String {
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
