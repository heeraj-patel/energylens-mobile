import XCTest

final class DiscoveryNavigationUITests: XCTestCase {
  func testCloudAccountPairsHubAndShowsSavedPlug() throws {
    continueAfterFailure = false
    guard
      let username = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_USERNAME"],
      !username.isEmpty,
      let password = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_PASSWORD"],
      !password.isEmpty,
      let pairingJson = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_PAIRING_JSON"],
      !pairingJson.isEmpty
    else {
      throw XCTSkip("Private Cloud credentials and one-time Hub enrollment were not supplied.")
    }

    let app = XCUIApplication(bundleIdentifier: "io.energylens.energylensMobile")
    addUIInterruptionMonitor(withDescription: "Local Network permission") { alert in
      guard alert.buttons["Allow"].exists else { return false }
      alert.buttons["Allow"].tap()
      return true
    }
    let reuseSession = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_REUSE_SESSION"] == "1"
    app.launchArguments = reuseSession ? [] : ["--energylens-reset-sign-in"]
    app.launch()

    let usernameField = app.textFields["Username"]
    let passwordField = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Password"))
      .firstMatch
    if !reuseSession {
      XCTAssertTrue(usernameField.waitForExistence(timeout: 90))
      usernameField.tap()
      usernameField.typeText(username)
      passwordField.tap()
      passwordField.typeText(password)
      app.buttons["Submit"].tap()
    }

    let settings = app.links
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings"))
      .firstMatch
    let chooseHome = app.staticTexts["Choose a home"]
    let routeReady = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in chooseHome.exists || settings.exists },
      object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [routeReady], timeout: 180), .completed)
    let demoHome = app.buttons
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "niksim"))
      .firstMatch
    if chooseHome.exists {
      let selectionRoute = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in demoHome.exists || settings.exists },
        object: app)
      XCTAssertEqual(XCTWaiter.wait(for: [selectionRoute], timeout: 60), .completed)
    }
    if demoHome.exists && !settings.exists {
      demoHome.tap()
    }
    XCTAssertTrue(settings.waitForExistence(timeout: 120))
    let settingsFrame = settings.frame
    let settingsCenter = app.coordinate(
      withNormalizedOffset: CGVector(
        dx: (settingsFrame.midX - app.frame.minX) / app.frame.width,
        dy: (settingsFrame.midY - app.frame.minY) / app.frame.height))
    settingsCenter.tap()
    if reuseSession {
      let accountIdentity = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label == %@", username))
        .firstMatch
      XCTAssertTrue(accountIdentity.waitForExistence(timeout: 60),
                    "Reused Cloud session did not belong to the approved account")
    }
    let manageDevices = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Manage Devices"))
      .firstMatch
    XCTAssertTrue(manageDevices.waitForExistence(timeout: 60))
    manageDevices.tap()
    let autoScan = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Auto Scan"))
      .firstMatch
    XCTAssertTrue(autoScan.waitForExistence(timeout: 60))
    autoScan.tap()

    XCTAssertTrue(app.staticTexts["Find a smart plug"].waitForExistence(timeout: 60),
                  "Auto Scan did not open the native smart plug discovery screen")
    let reusePairing = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_REUSE_PAIRING"] == "1"
    if !reusePairing {
      let pair = app.buttons
        .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Pair with"))
        .firstMatch
      XCTAssertTrue(pair.waitForExistence(timeout: 60), "Hub pairing action did not render")
      pair.tap()
      let operatorJson = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label == %@", "Paste hub pairing JSON"))
        .firstMatch
      XCTAssertTrue(operatorJson.waitForExistence(timeout: 30), "Hub JSON field did not render")
      operatorJson.tap()
      operatorJson.typeText(pairingJson)
      app.buttons["Verify and pair"].tap()
    }

    let connected = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Hub connected"))
      .firstMatch
    XCTAssertTrue(connected.waitForExistence(timeout: 90), "Hub pairing did not connect")
    XCTAssertTrue(app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Cloud home: niksim"))
      .firstMatch.exists, "Paired Hub was not scoped to the selected Cloud home")
    let saved = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Kitchen Mixer Plug"))
      .firstMatch
    for _ in 0..<5 {
      if saved.exists { break }
      app.swipeUp()
    }
    XCTAssertTrue(saved.waitForExistence(timeout: 90), "Saved KS8 plug was not visible")
    let model = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "KP115(US)"))
      .firstMatch
    XCTAssertTrue(model.exists, "Saved plug model KP115(US) was not visible")
    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "Cloud account paired Hub with saved KS8 plug"
    evidence.lifetime = .keepAlways
    add(evidence)

    let back = app.buttons["Back"]
    XCTAssertTrue(back.exists, "Discovery back navigation was unavailable")
    back.tap()
    let monitored = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Kitchen Mixer Plug"))
      .firstMatch
    XCTAssertTrue(monitored.waitForExistence(timeout: 90),
                  "Saved KS8 plug did not appear in the monitored devices list")
    let settingsEvidence = XCTAttachment(screenshot: app.screenshot())
    settingsEvidence.name = "Settings monitored KS8 plug"
    settingsEvidence.lifetime = .keepAlways
    add(settingsEvidence)
  }

  func testCloudSignInStartsQuietlyAndShowsSafeFailure() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "io.energylens.energylensMobile")
    addUIInterruptionMonitor(withDescription: "Local Network permission") { alert in
      guard alert.buttons["Allow"].exists else { return false }
      alert.buttons["Allow"].tap()
      return true
    }
    app.launchArguments = ["--energylens-reset-sign-in"]
    app.launch()

    let username = app.textFields["Username"]
    let password = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Password"))
      .firstMatch
    let submit = app.buttons["Submit"]
    let error = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Internal error, Try again later"))
      .firstMatch
    XCTAssertTrue(username.waitForExistence(timeout: 90), "Username field did not render")
    XCTAssertTrue(password.exists, "Password field did not render")
    XCTAssertTrue(submit.exists, "Submit button did not render")
    XCTAssertFalse(error.exists,
                   "Startup showed an authentication error before submission")

    let initial = XCTAttachment(screenshot: app.screenshot())
    initial.name = "Cloud sign-in initial"
    initial.lifetime = .keepAlways
    add(initial)

    username.tap()
    username.typeText("invalid@example.invalid")
    password.tap()
    password.typeText("invalid-dummy-password")
    let entered = XCTAttachment(screenshot: app.screenshot())
    entered.name = "Cloud sign-in with invalid credentials before submission"
    entered.lifetime = .keepAlways
    add(entered)
    submit.tap()

    XCTAssertTrue(error.waitForExistence(timeout: 60), "Safe sign-in failure did not appear")
    let failure = XCTAttachment(screenshot: app.screenshot())
    failure.name = "Cloud sign-in safe failure"
    failure.lifetime = .keepAlways
    add(failure)
  }

  func testCloudLocalAccountSignsInShowsEmailAndSignsOut() throws {
    continueAfterFailure = false
    guard
      let username = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_USERNAME"],
      !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let password = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_PASSWORD"],
      !password.isEmpty
    else {
      throw XCTSkip("Private Cloud test credentials were not supplied to the test runner.")
    }

    let app = XCUIApplication(bundleIdentifier: "io.energylens.energylensMobile")
    addUIInterruptionMonitor(withDescription: "Local Network permission") { alert in
      guard alert.buttons["Allow"].exists else { return false }
      alert.buttons["Allow"].tap()
      return true
    }
    app.launchArguments = ["--energylens-reset-sign-in"]
    app.launch()

    let usernameField = app.textFields["Username"]
    let passwordField = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Password"))
      .firstMatch
    let submit = app.buttons["Submit"]
    XCTAssertTrue(usernameField.waitForExistence(timeout: 300), "Sign-in form did not render")
    XCTAssertTrue(passwordField.exists, "Password field did not render")
    let startupError = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Internal error, Try again later"))
      .firstMatch
    XCTAssertFalse(startupError.exists,
                   "Startup showed an authentication error before submission")

    usernameField.tap()
    usernameField.typeText(username)
    passwordField.tap()
    passwordField.typeText(password)
    submit.tap()

    let chooseHome = app.staticTexts["Choose a home"]
    let settings = app.links
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings"))
      .firstMatch
    let routeReady = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in chooseHome.exists || settings.exists },
      object: app)
    let routeResult = XCTWaiter.wait(for: [routeReady], timeout: 300)
    XCTAssertEqual(routeResult, .completed, "Cloud sign-in did not reach a home or Settings")
    let chooserTileLabel = NSPredicate(
      format: "label CONTAINS[c] %@ AND label MATCHES[c] %@",
      "niksim",
      ".*[0-9]{5}.*[A-Za-z_]+/[A-Za-z_]+.*")
    let demoHome = app.buttons
      .matching(chooserTileLabel)
      .firstMatch
    if chooseHome.exists {
      let selectionRoute = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in demoHome.exists || settings.exists },
        object: app)
      let selectionResult = XCTWaiter.wait(for: [selectionRoute], timeout: 60)
      XCTAssertEqual(selectionResult, .completed,
                     "Cloud home chooser did not show its matching tile or finish restoring Home")
    }
    if demoHome.exists && !settings.exists {
      demoHome.tap()
    }

    XCTAssertTrue(settings.waitForExistence(timeout: 300), "Settings navigation did not render")
    let settingsFrame = settings.frame
    XCTAssertTrue(settingsFrame.intersects(app.frame), "Settings link was outside the app viewport")
    let settingsCenter = app.coordinate(
      withNormalizedOffset: CGVector(
        dx: (settingsFrame.midX - app.frame.minX) / app.frame.width,
        dy: (settingsFrame.midY - app.frame.minY) / app.frame.height))
    settingsCenter.tap()

    let accountIdentity = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", username))
      .firstMatch
    XCTAssertTrue(accountIdentity.waitForExistence(timeout: 300), "Signed-in account identity was not visible in Settings")
    XCTAssertFalse(passwordField.exists, "Password field remained after sign-in")

    let profile = XCTAttachment(screenshot: app.screenshot())
    profile.name = "Cloud account profile"
    profile.lifetime = .keepAlways
    add(profile)

    let signOut = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Sign Out"))
      .firstMatch
    XCTAssertTrue(signOut.waitForExistence(timeout: 60), "Sign Out was not available in Settings")
    let viewport = app.frame
    var signOutFrame = signOut.frame
    for _ in 0..<4 {
      let center = CGPoint(x: signOutFrame.midX, y: signOutFrame.midY)
      if viewport.contains(center) { break }
      app.swipeUp()
      signOutFrame = signOut.frame
    }
    let signOutCenter = CGPoint(x: signOutFrame.midX, y: signOutFrame.midY)
    XCTAssertTrue(viewport.contains(signOutCenter), "Sign Out was not visible in Settings")
    let signOutCoordinate = app.coordinate(
      withNormalizedOffset: CGVector(
        dx: (signOutFrame.midX - viewport.minX) / viewport.width,
        dy: (signOutFrame.midY - viewport.minY) / viewport.height))
    signOutCoordinate.tap()

    XCTAssertTrue(usernameField.waitForExistence(timeout: 300), "Sign-out did not return to the sign-in form")
    XCTAssertTrue(passwordField.exists, "Fresh sign-in form did not show a password field")
    XCTAssertFalse(accountIdentity.exists, "Signed-in account identity remained visible after sign-out")
    let freshForm = XCTAttachment(screenshot: app.screenshot())
    freshForm.name = "Cloud sign-in after sign-out"
    freshForm.lifetime = .keepAlways
    add(freshForm)
  }

  func testLocalPilotSettingsToNearbyDevices() {
    let app = XCUIApplication(bundleIdentifier: "io.energylens.energylensMobile")
    app.launch()

    func labeled(_ label: String) -> XCUIElement {
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS[c] %@", label))
        .firstMatch
    }

    let settings = labeled("Settings")
    XCTAssertTrue(settings.waitForExistence(timeout: 90), "Settings navigation did not render")
    settings.tap()

    let manageDevices = labeled("Manage Devices")
    XCTAssertTrue(manageDevices.waitForExistence(timeout: 30), "Manage Devices did not render")
    manageDevices.tap()

    let autoScan = labeled("Auto Scan")
    XCTAssertTrue(autoScan.waitForExistence(timeout: 30), "Auto Scan did not render")
    autoScan.tap()

    XCTAssertTrue(labeled("Nearby devices").waitForExistence(timeout: 30))
    XCTAssertTrue(labeled("Add").exists)
  }
}
