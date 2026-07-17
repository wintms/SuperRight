import AppKit
import Foundation

enum FileKind {
    case text
    case markdown
    case word
    case json

    var baseName: String {
        switch self {
        case .text: "新建文本文档"
        case .markdown: "新建 Markdown"
        case .word: "新建 Word 文档"
        case .json: "新建 JSON"
        }
    }

    var pathExtension: String {
        switch self {
        case .text: "txt"
        case .markdown: "md"
        case .word: "docx"
        case .json: "json"
        }
    }

    func contents() throws -> Data {
        switch self {
        case .text, .markdown:
            return Data()
        case .json:
            return Data("{\n  \n}\n".utf8)
        case .word:
            let document = NSAttributedString(string: "")
            return try document.data(
                from: NSRange(location: 0, length: document.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
        }
    }
}

struct FileCreator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func create(_ kind: FileKind, in directory: URL) throws -> URL {
        let destination = availableURL(for: kind, in: directory)
        let data = try kind.contents()
        try data.write(to: destination, options: .withoutOverwriting)
        return destination
    }

    private func availableURL(for kind: FileKind, in directory: URL) -> URL {
        var suffix = 1
        var candidate = directory
            .appendingPathComponent(kind.baseName, isDirectory: false)
            .appendingPathExtension(kind.pathExtension)

        while fileManager.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = directory
                .appendingPathComponent("\(kind.baseName) \(suffix)", isDirectory: false)
                .appendingPathExtension(kind.pathExtension)
        }

        return candidate
    }
}

