import XCTest
@testable import SuperRight

final class FileCreatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperRightTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testCreatesPlainTextAndExpandsVariables() throws {
        let template = FileTemplate(
            name: "测试",
            fileExtension: "md",
            content: "# {{filename}}\n目录：{{directory}}\n"
        )
        let creator = FileCreator()

        let url = try creator.create(template: template, requestedName: "说明.md", in: directory)

        XCTAssertEqual(url.lastPathComponent, "说明.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("# 说明"))
        XCTAssertTrue(content.contains(directory.lastPathComponent))
    }

    func testAddsNumberWhenFileAlreadyExists() throws {
        let template = FileTemplate(name: "文本", fileExtension: "txt")
        let creator = FileCreator()

        let first = try creator.create(template: template, requestedName: "记录", in: directory)
        let second = try creator.create(template: template, requestedName: "记录", in: directory)

        XCTAssertEqual(first.lastPathComponent, "记录.txt")
        XCTAssertEqual(second.lastPathComponent, "记录 2.txt")
    }

    func testRejectsInvalidFileName() throws {
        let template = FileTemplate(name: "文本", fileExtension: "txt")

        XCTAssertThrowsError(
            try FileCreator().create(template: template, requestedName: "a/b", in: directory)
        ) { error in
            guard case .invalidName = error as? FileCreationError else {
                return XCTFail("Expected invalidName, got \(error)")
            }
        }
    }

    func testCreatesValidWordPackage() throws {
        let template = FileTemplate(
            name: "Word",
            fileExtension: "docx",
            content: "Hello",
            format: .word
        )

        let url = try FileCreator().create(template: template, requestedName: "Document", in: directory)
        let data = try Data(contentsOf: url)

        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(Array(data.prefix(2)), Array("PK".utf8))
    }

    func testSettingsDecoderRestoresMissingFields() throws {
        let json = #"{"monitoredDirectories":[{"path":"/tmp"}]}"#.data(using: .utf8)!

        let settings = try JSONDecoder().decode(SuperRightSettings.self, from: json)

        XCTAssertEqual(settings.menuOrder, MenuSection.allCases)
        XCTAssertEqual(settings.templates.count, FileTemplate.defaults.count)
        XCTAssertTrue(settings.asksForFileName)
    }

    func testSettingsRoundTripThroughDistributedNotificationPayload() throws {
        var settings = SuperRightSettings.defaults
        settings.terminalApplicationID = "warp"
        settings.usesSubmenu = false
        let userInfo = try XCTUnwrap(MonitoringConfiguration.notificationUserInfo(for: settings))
        let notification = Notification(
            name: MonitoringConfiguration.didChangeNotification,
            object: nil,
            userInfo: userInfo
        )

        let decoded = try XCTUnwrap(MonitoringConfiguration.settings(from: notification))

        XCTAssertEqual(decoded.terminalApplicationID, "warp")
        XCTAssertFalse(decoded.usesSubmenu)
    }
}
