import XCTest

@MainActor final class ConnectTodoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func require(_ condition: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else { XCTFail("Required UI state was not reached", file: file, line: line); throw NativeHarness.HarnessError.rejected }
    }
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
    private func begin(_ app: XCUIApplication, manager: Bool = false) throws {
        let address = app.textFields["ship-url"]
        try require(address.waitForExistence(timeout: 10)); address.tap()
        if let old = address.value as? String, old.hasPrefix("https:") { address.typeKey("a", modifierFlags: .command); address.typeText(XCUIKeyboardKey.delete.rawValue) }
        address.typeText((try XCTUnwrap(ProcessInfo.processInfo.environment["CONNECT_TEST_ORIGIN"])) + (manager ? "/apps/connect/" : ""))
        app.buttons["connect-urbit"].tap()
        if manager { try require(app.buttons["Use ship address"].waitForExistence(timeout: 5)); app.buttons["Use ship address"].tap() }
        let button = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Continue"]
        if button.waitForExistence(timeout: 2) { button.tap() }
    }
    private func login(_ app: XCUIApplication) throws {
        let login = app.buttons["Log in to ship"]
        if login.waitForExistence(timeout: 5) { login.tap() }
        else if safari.buttons["Log in to ship"].exists { safari.buttons["Log in to ship"].tap() }
        let local = app.secureTextFields.firstMatch
        let field = local.waitForExistence(timeout: 2) ? local : safari.secureTextFields.firstMatch
        if field.exists {
            let path = try XCTUnwrap(ProcessInfo.processInfo.environment["CONNECT_TEST_CREDENTIALS_PATH"])
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: String])
            field.tap(); field.typeText(try XCTUnwrap(values["code"]))
            if safari.buttons["Done"].waitForExistence(timeout: 2) { safari.buttons["Done"].tap() }
            else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
            else { safari.buttons["Continue"].tap() }
            if safari.alerts["Save Password?"].waitForExistence(timeout: 2) { safari.tap() }
            let submitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
            if XCTWaiter().wait(for: [submitted], timeout: 3) != .completed {
                // Safari can use the first tap to dismiss its keyboard accessory.
                // Submit again only while the original login form remains visible.
                let retry = safari.buttons["Continue"]
                if retry.exists && retry.isHittable { retry.tap() }
                if safari.alerts["Save Password?"].waitForExistence(timeout: 2) { safari.tap() }
            }
        }
    }
    private func consent(_ label: String, app: XCUIApplication) throws {
        let local = app.buttons[label]
        let button = local.waitForExistence(timeout: 4) ? local : safari.buttons[label]
        try require(button.waitForExistence(timeout: 5))
        if !button.isHittable { safari.swipeUp() }
        button.tap()
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func saved(_ app: XCUIApplication) throws { try require(app.staticTexts["Saved on your ship"].waitForExistence(timeout: 15)) }
    private func addTask(_ title: String, app: XCUIApplication) throws {
        let field = app.textFields["task-title"]; try require(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(title); app.buttons["add-task"].tap()
        try require(app.staticTexts[title].waitForExistence(timeout: 5))
    }
    private func newList(_ title: String, app: XCUIApplication) throws {
        app.buttons["new-list"].tap(); let name = app.alerts.textFields.firstMatch
        try require(name.waitForExistence(timeout: 3)); name.typeText(title); app.alerts.buttons["Create"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        try require(row.waitForExistence(timeout: 5)); row.tap()
    }
    func testNativeWorkflowRecoveryAndRevocation() async throws {
        addUIInterruptionMonitor(withDescription: "Do not save disposable ship credentials") { alert in
            if alert.buttons["Not Now"].exists { alert.buttons["Not Now"].tap(); return true }; return false
        }
        let harness = try NativeHarness(); _ = try await harness.call("reset")
        let app = XCUIApplication(); app.launch()
        try begin(app, manager: true)
        let cancel = safari.buttons["Close"]
        try require(cancel.waitForExistence(timeout: 5)); cancel.tap()
        try require(app.alerts["Connect Todo"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        try begin(app); try login(app); try consent("Deny", app: app)
        try require(app.staticTexts["You denied the connection. No app access was granted."].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        try begin(app); try login(app); try consent("Approve connection", app: app)
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 15))
        try require(app.staticTexts["ship-origin"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["ship-origin"].label, (try XCTUnwrap(ProcessInfo.processInfo.environment["CONNECT_TEST_ORIGIN"])) + "/")
        try require(app.staticTexts["Development ship"].exists)
        try newList("Personal", app: app)
        try require(app.staticTexts["Nothing to remember yet."].waitForExistence(timeout: 5))
        try addTask("Buy milk", app: app); try saved(app)
        app.buttons["Complete Buy milk"].tap(); try require(app.buttons["Mark Buy milk incomplete"].waitForExistence(timeout: 5)); try saved(app)
        app.swipeDown(); capture("Personal-Buy-milk-saved", app: app)
        var document = try await harness.document(titled: "Personal")
        var data = try XCTUnwrap(document["data"] as? [String: Any]); var tasks = try XCTUnwrap(data["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1); XCTAssertEqual(tasks[0]["completed"] as? Bool, true)
        tasks[0]["title"] = "Buy oat milk"; data["tasks"] = tasks
        let started = Date(); try await harness.replace(document, data: data)
        try require(app.staticTexts["Buy oat milk"].waitForExistence(timeout: 2)); XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        capture("owner-edit-visible-native", app: app)
        app.staticTexts["Buy oat milk"].press(forDuration: 1)
        app.buttons["Edit task"].tap()
        let title = app.descendants(matching: .any)["edit-task-title"].firstMatch; try require(title.waitForExistence(timeout: 3)); title.tap()
        title.typeKey("a", modifierFlags: .command); title.typeText("Buy almond milk")
        app.buttons["Save"].tap(); try require(app.staticTexts["Buy almond milk"].waitForExistence(timeout: 5)); try saved(app)
        app.staticTexts["Buy almond milk"].swipeLeft(); app.buttons["Delete"].firstMatch.tap(); try saved(app)
        XCTAssertFalse(app.staticTexts["Buy almond milk"].exists); try addTask("Buy milk", app: app); try saved(app)
        app.terminate(); app.launch()
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Personal")).firstMatch.tap()
        try require(app.staticTexts["Buy milk"].waitForExistence(timeout: 5)); try saved(app)
        document = try await harness.document(titled: "Personal")
        _ = try await harness.call("proxy-off")
        try addTask("Offline reminder", app: app)
        XCTAssertFalse(app.staticTexts["Saved on your ship"].exists)
        try require(app.staticTexts["Offline · edits saved on this iPhone"].waitForExistence(timeout: 50))
        capture("offline-durable-draft", app: app); app.terminate()
        data = try XCTUnwrap(document["data"] as? [String: Any]); data["title"] = "Changed on ship"
        try await harness.replace(document, data: data)
        _ = try await harness.call("proxy-on"); app.launch()
        try require(app.staticTexts["Changes need your attention"].waitForExistence(timeout: 15))
        app.buttons["review-change"].firstMatch.tap()
        try require(app.staticTexts["Two versions need a decision"].waitForExistence(timeout: 5)); capture("conflict-both-versions", app: app)
        for _ in 0..<4 {
            if app.buttons["Save as a new list"].exists && app.buttons["Save as a new list"].isHittable { break }
            app.swipeUp()
        }
        try require(app.buttons["Save as a new list"].exists)
        capture("conflict-actions", app: app)
        app.buttons["Save as a new list"].tap(); try saved(app)
        let recovered = try await harness.document(titled: "Personal")
        let recoveredTasks = try XCTUnwrap((recovered["data"] as? [String: Any])?["tasks"] as? [[String: Any]])
        XCTAssertEqual(recoveredTasks.filter { $0["title"] as? String == "Offline reminder" }.count, 1)
        let rows1 = try await harness.documents(); XCTAssertEqual(rows1.count, 2)
        try newList("Disposable", app: app); try saved(app)
        let longTask = "Prepare the weekend grocery list and remember the reusable shopping bags."
        try addTask(longTask, app: app); try saved(app); app.swipeDown(); capture("long-task-text", app: app)
        app.buttons["List options"].tap(); app.buttons["Rename list"].tap()
        let listName = app.alerts.textFields.firstMatch; listName.tap(); listName.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .command); listName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Disposable".count) + "Remove me")
        app.alerts.buttons["Save"].tap(); try require(app.navigationBars["Remove me"].waitForExistence(timeout: 5)); try saved(app)
        app.buttons["List options"].tap(); app.buttons["Delete list"].tap(); app.buttons["Delete list"].tap()
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 5)); try saved(app)
        let rows2 = try await harness.documents(); XCTAssertEqual(rows2.count, 2)
        let unsupported = try await harness.document(titled: "Changed on ship")
        try await harness.replace(unsupported, data: ["futureSchema": true, "privateValue": "Preserved"])
        try require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unsupported data")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unsupported data")).firstMatch.tap()
        try require(app.staticTexts["Unsupported data"].waitForExistence(timeout: 5)); capture("unsupported-data-preserved", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection, .contrast, .textClipped])
        _ = try await harness.call("appearance", extra: ["style": "dark"])
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 10)); capture("large-type-dark-lists", app: app)
        _ = try await harness.call("revoke")
        try require(app.staticTexts["Access revoked"].waitForExistence(timeout: 10)); capture("revoked-native", app: app)
        let rows3 = try await harness.documents(); XCTAssertEqual(rows3.count, 2)
    }
    func testPreservedInstallUpgradeAndRejectedCapacityInput() async throws {
        let harness = try NativeHarness(); _ = try await harness.call("reset")
        let baseline = try await harness.call("fresh-baseline-app")
        XCTAssertEqual(baseline["baselineLaunched"] as? Bool, true)
        let app = XCUIApplication()
        // The control harness launched the prior app with its matching SDK runtime.
        // Wait for that process instead of relaunching it without the runtime.
        try require(app.wait(for: .runningForeground, timeout: 15))
        try begin(app); try login(app); try consent("Approve connection", app: app)
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 15))
        try newList("Preserved install", app: app); try saved(app)
        _ = try await harness.call("proxy-off")
        try addTask("Unsent upgrade task", app: app)
        try require(app.staticTexts["Offline · edits saved on this iPhone"].waitForExistence(timeout: 50)); app.terminate()
        let before = try await harness.call("local-storage")
        XCTAssertEqual(before["schema"] as? Int, 1); XCTAssertEqual(before["pendingCount"] as? Int, 1)
        _ = try await harness.call("install-app-update")
        app.launch()
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 10)); app.terminate()
        let after = try await harness.call("local-storage")
        XCTAssertEqual(after["schema"] as? Int, 2); XCTAssertEqual(after["requestHashes"] as? [String], before["requestHashes"] as? [String])
        let full = try await harness.call("fill-outbox-capacity"); XCTAssertEqual(full["pendingCount"] as? Int, 1000)
        app.launch(); try require(app.navigationBars["My lists"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Preserved install")).firstMatch.tap()
        let field = app.textFields["task-title"]; try require(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Keep this rejected input"); app.buttons["add-task"].tap()
        try require(app.staticTexts["This iPhone has 1,000 pending changes. Your new input is kept. Synchronize or review existing drafts before adding another."].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap(); XCTAssertEqual(field.value as? String, "Keep this rejected input"); capture("capacity-input-retained", app: app); app.terminate()
        let restored = try await harness.call("restore-outbox-capacity"); XCTAssertEqual(restored["pendingCount"] as? Int, 1)
        _ = try await harness.call("proxy-on"); app.launch(); try saved(app)
        let document = try await harness.document(titled: "Preserved install")
        let tasks = try XCTUnwrap((document["data"] as? [String: Any])?["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1); XCTAssertEqual(tasks[0]["title"] as? String, "Unsent upgrade task")
        _ = try await harness.call("record-app-update", extra: ["before": before,"after": after])
    }
    func testRealShipWorkflowAndCompatibleDeskUpdate() async throws {
        let harness = try NativeHarness(); _ = try await harness.call("reset")
        let app = XCUIApplication(); app.launch()
        try begin(app, manager: true); try login(app); try consent("Approve connection", app: app)
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Development ship"].exists)
        try newList("Reference ship list", app: app)
        try addTask("Reference task", app: app); try saved(app)
        app.buttons["Complete Reference task"].tap(); try saved(app)
        capture("real-ship-saved", app: app)
        _ = try await harness.call("proxy-off")
        try addTask("Unsent during desk update", app: app)
        try require(app.staticTexts["Offline · edits saved on this iPhone"].waitForExistence(timeout: 50)); app.terminate()
        let before = try await harness.call("local-storage"); XCTAssertEqual(before["pendingCount"] as? Int, 1)
        _ = try await harness.call("proxy-on")
        let update = try await harness.call("desk-update"); XCTAssertEqual(update["passed"] as? Bool, true)
        let after = try await harness.call("local-storage")
        XCTAssertEqual(after["requestHashes"] as? [String], before["requestHashes"] as? [String])
        XCTAssertEqual(after["mutationIDsSHA256"] as? String, before["mutationIDsSHA256"] as? String)
        app.launch(); try saved(app)
        let document = try await harness.document(titled: "Reference ship list")
        let tasks = try XCTUnwrap((document["data"] as? [String: Any])?["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.filter { $0["title"] as? String == "Unsent during desk update" }.count, 1)
        XCTAssertEqual(tasks.count, 2); capture("real-ship-desk-update-catch-up", app: app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reference ship list")).firstMatch.tap()
        _ = try await harness.call("proxy-off"); try addTask("Review this offline conflict", app: app)
        try require(app.staticTexts["Offline · edits saved on this iPhone"].waitForExistence(timeout: 50)); app.terminate()
        var data = try XCTUnwrap(document["data"] as? [String: Any]); data["title"] = "Changed by the owner"
        try await harness.replace(document, data: data)
        _ = try await harness.call("proxy-on"); app.launch()
        try require(app.staticTexts["Changes need your attention"].waitForExistence(timeout: 15))
        app.buttons["review-change"].firstMatch.tap()
        try require(app.staticTexts["Two versions need a decision"].waitForExistence(timeout: 5)); capture("real-ship-conflict", app: app)
        for _ in 0..<4 {
            if app.buttons["Save as a new list"].exists && app.buttons["Save as a new list"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["Save as a new list"].tap(); try saved(app)
        let recovered = try await harness.document(titled: "Reference ship list")
        let recoveredTasks = try XCTUnwrap((recovered["data"] as? [String: Any])?["tasks"] as? [[String: Any]])
        XCTAssertEqual(recoveredTasks.filter { $0["title"] as? String == "Review this offline conflict" }.count, 1)
        try newList("Disposable real list", app: app); try saved(app)
        app.buttons["List options"].tap(); app.buttons["Delete list"].tap(); app.buttons["Delete list"].tap()
        try require(app.navigationBars["My lists"].waitForExistence(timeout: 5)); try saved(app)
        let beforeRevocation = try await harness.documents(); XCTAssertEqual(beforeRevocation.count, 2)
        _ = try await harness.call("revoke")
        try require(app.staticTexts["Access revoked"].waitForExistence(timeout: 15)); capture("real-ship-revoked", app: app)
        app.buttons["Reconnect with Urbit"].tap(); try login(app); try consent("Approve connection", app: app)
        try saved(app); let afterReauthorization = try await harness.documents(); XCTAssertEqual(afterReauthorization.count, 2)
    }
}
