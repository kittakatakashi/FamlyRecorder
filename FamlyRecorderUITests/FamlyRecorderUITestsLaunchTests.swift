//
//  FamlyRecorderUITestsLaunchTests.swift
//  FamlyRecorderUITests
//
//  Created by kikuchitakashi on 2026/04/05.
//

import XCTest

final class FamlyRecorderUITestsLaunchTests: XCTestCase {
    private var shouldRunUITests: Bool {
        ProcessInfo.processInfo.environment["RUN_FULL_UI_TESTS"] == "1"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        if !shouldRunUITests {
            throw XCTSkip("UI起動テストは重いため既定ではスキップします。")
        }

        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
