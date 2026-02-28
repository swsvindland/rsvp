//
//  Book.swift
//  rsvp
//
//  Created by Sam Svindland on 2/28/26.
//

import Foundation
import SwiftData

enum BookSourceType: String, Codable, CaseIterable, Identifiable {
    case text
    case epub

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .epub:
            return "EPUB"
        }
    }
}

@Model
final class Book {
    var title: String
    var sourceType: BookSourceType
    var text: String
    var epubFileName: String?
    var epubFilePath: String?
    var isActive: Bool
    var currentWordIndex: Int
    var progress: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String,
        sourceType: BookSourceType,
        text: String = "",
        epubFileName: String? = nil,
        epubFilePath: String? = nil,
        isActive: Bool = false,
        currentWordIndex: Int = 0,
        progress: Double = 0.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.sourceType = sourceType
        self.text = text
        self.epubFileName = epubFileName
        self.epubFilePath = epubFilePath
        self.isActive = isActive
        self.currentWordIndex = currentWordIndex
        self.progress = progress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
