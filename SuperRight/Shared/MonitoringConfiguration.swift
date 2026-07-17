import Foundation
import Darwin

enum MonitoringConfiguration {
    static let didChangeNotification = Notification.Name("SuperRightMonitoringDirectoriesDidChange")

    static let defaultPaths = [
        "/Users",
        "/Volumes",
        "/Applications",
        "/Library",
        "/System",
        "/private",
        "/opt"
    ]

    private struct StoredConfiguration: Codable {
        let paths: [String]
    }

    static func loadPaths() -> [String] {
        guard let data = try? Data(contentsOf: configurationURL),
              let configuration = try? JSONDecoder().decode(StoredConfiguration.self, from: data),
              !configuration.paths.isEmpty else {
            return defaultPaths
        }

        return normalized(configuration.paths)
    }

    static func save(paths: [String]) throws {
        let paths = normalized(paths)
        guard !paths.isEmpty else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(StoredConfiguration(paths: paths))
        try data.write(to: configurationURL, options: .atomic)
    }

    private static func normalized(_ paths: [String]) -> [String] {
        Array(Set(paths.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
                .path(percentEncoded: false)
        }))
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static var configurationURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support/SuperRight", isDirectory: true)
            .appendingPathComponent("monitoring.json", isDirectory: false)
    }

    private static var realHomeDirectory: URL {
        if let passwordEntry = getpwuid(getuid()),
           let homePath = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}

