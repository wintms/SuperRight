import AppKit
import Foundation

enum FileCreationError: LocalizedError {
    case invalidName
    case directoryUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidName:
            SRLocalized("文件名不能为空，也不能包含“/”。")
        case .directoryUnavailable:
            SRLocalized("目标目录不存在或当前没有写入权限。")
        }
    }
}

struct FileCreator {
    private let fileManager: FileManager
    private let now: () -> Date

    init(fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    func create(
        template: FileTemplate,
        requestedName: String,
        in directory: URL
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: directory.path) else {
            throw FileCreationError.directoryUnavailable
        }

        let baseName = try sanitizedBaseName(requestedName, fileExtension: template.fileExtension)
        let destination = availableURL(
            baseName: baseName,
            fileExtension: template.fileExtension,
            in: directory
        )
        let data = try contents(
            for: template,
            baseName: destination.deletingPathExtension().lastPathComponent,
            directory: directory
        )

        do {
            try data.write(to: destination, options: .withoutOverwriting)
            return destination
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // A different process may have created the candidate between the
            // availability check and the write. Retry once with a fresh name.
            let retryURL = availableURL(
                baseName: baseName,
                fileExtension: template.fileExtension,
                in: directory
            )
            try data.write(to: retryURL, options: .withoutOverwriting)
            return retryURL
        }
    }

    func suggestedBaseName(for template: FileTemplate) -> String {
        String(format: SRLocalized("新建%@"), template.name)
    }

    private func sanitizedBaseName(_ requestedName: String, fileExtension: String) throws -> String {
        var value = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            value.removeLast(fileExtension.count + 1)
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("/"), value != ".", value != ".." else {
            throw FileCreationError.invalidName
        }
        return value
    }

    private func availableURL(baseName: String, fileExtension: String, in directory: URL) -> URL {
        var suffix = 1
        var candidate = destinationURL(
            baseName: baseName,
            suffix: nil,
            fileExtension: fileExtension,
            directory: directory
        )

        while fileManager.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = destinationURL(
                baseName: baseName,
                suffix: suffix,
                fileExtension: fileExtension,
                directory: directory
            )
        }
        return candidate
    }

    private func destinationURL(
        baseName: String,
        suffix: Int?,
        fileExtension: String,
        directory: URL
    ) -> URL {
        let name = suffix.map { "\(baseName) \($0)" } ?? baseName
        return directory
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension(fileExtension)
    }

    private func contents(for template: FileTemplate, baseName: String, directory: URL) throws -> Data {
        let expandedContent = expand(
            template.content,
            baseName: baseName,
            directory: directory,
            date: now()
        )

        switch template.format {
        case .plainText:
            return Data(expandedContent.utf8)
        case .word:
            let document = NSAttributedString(string: expandedContent)
            return try document.data(
                from: NSRange(location: 0, length: document.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
        }
    }

    private func expand(_ content: String, baseName: String, directory: URL, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.dateFormat = "HH:mm:ss"

        return content
            .replacingOccurrences(of: "{{filename}}", with: baseName)
            .replacingOccurrences(of: "{{directory}}", with: directory.lastPathComponent)
            .replacingOccurrences(of: "{{path}}", with: directory.path(percentEncoded: false))
            .replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "{{time}}", with: timeFormatter.string(from: date))
            .replacingOccurrences(of: "{{user}}", with: NSUserName())
    }
}
