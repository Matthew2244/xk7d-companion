import XCTest
@testable import XK7DCore

/// 1.0.0 to 1.0.3 loaded the table through SwiftPM's Bundle.module, which only works on the Mac that
/// built the app. The table is now compiled in; these keep it that way and keep it in step.
final class EmbeddedTableTests: XCTestCase {
    func testTheCompiledInTableMatchesTheJSONFile() throws {
        let json = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/XK7DCore/Resources/parameters.json")
        // A multiline literal drops the file's final newline.
        XCTAssertEqual(parameterTableJSON + "\n", try String(contentsOf: json, encoding: .utf8),
                       "run python3 tools/generate_parameters.py")
    }

    func testSharedLoadsWithoutResources() {
        XCTAssertNil(ParameterDatabase.loadError)
        XCTAssertEqual(ParameterDatabase.shared.parameters.count, 537)
    }

    func testNoSwiftPMResourceBundle() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Package.swift")
        let text = try String(contentsOf: package, encoding: .utf8)
        XCTAssertFalse(text.contains("resources: ["), "Bundle.module breaks the app on other Macs")
        let sources = package.deletingLastPathComponent().appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let f as URL in files where f.pathExtension == "swift" {
            let code = try String(contentsOf: f, encoding: .utf8)
            XCTAssertFalse(code.contains("Bundle" + ".module."), f.lastPathComponent)
        }
    }
}
