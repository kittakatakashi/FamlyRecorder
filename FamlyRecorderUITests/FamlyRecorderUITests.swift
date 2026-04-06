//
//  FamlyRecorderUITests.swift
//  FamlyRecorderUITests
//
//  Created by kikuchitakashi on 2026/04/05.
//

import XCTest

final class FamlyRecorderUITests: XCTestCase {
    private var shouldRunUITests: Bool {
        ProcessInfo.processInfo.environment["RUN_FULL_UI_TESTS"] == "1"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInitialScreenShowsRecordingControlsAndDestination() throws {
        try skipUnlessRunningFullUITests()

        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        XCTAssertTrue(app.navigationBars["Famly Recorder"].exists)
        XCTAssertTrue(app.buttons["recordButton"].exists)
        XCTAssertTrue(app.staticTexts["permissionStatusLabel"].exists)
        XCTAssertTrue(app.staticTexts["bufferStatusLabel"].exists)
        XCTAssertTrue(app.staticTexts["recordingStatusLabel"].exists)
        XCTAssertTrue(app.staticTexts["saveDestinationText"].exists)
        XCTAssertEqual(app.buttons["recordButton"].label, "録音開始")
    }

    @MainActor
    func testRecordButtonTogglesAndShowsSavedFileAfterStop() throws {
        try skipUnlessRunningFullUITests()

        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 2))

        recordButton.tap()
        XCTAssertEqual(recordButton.label, "録音停止")
        XCTAssertTrue(app.staticTexts["recordingStatusLabel"].label.contains("録音中"))

        recordButton.tap()
        XCTAssertEqual(recordButton.label, "録音開始")
        XCTAssertTrue(app.staticTexts["savedFileLabel"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["savedFileLabel"].label.contains(".wav"))
    }

    @MainActor
    func testLaunchPerformance() throws {
        throw XCTSkip("起動計測は負荷が高いため常時実行しません。必要時のみ Instruments / Xcode から個別に実行してください。")
    }

    private func skipUnlessRunningFullUITests() throws {
        if !shouldRunUITests {
            throw XCTSkip("UIテストは重いため既定ではスキップします。実行時は RUN_FULL_UI_TESTS=1 を指定してください。")
        }
    }
}
