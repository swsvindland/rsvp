//
//  BookDraft.swift
//  rsvp
//
//  Created by Sam Svindland on 2/27/26.
//

import Foundation

struct BookDraft {
    var title: String = ""
    var sourceType: BookSourceType = .text
    var text: String = ""
    var epubFileName: String?
    var epubFilePath: String?
    var isActive: Bool = false
}
