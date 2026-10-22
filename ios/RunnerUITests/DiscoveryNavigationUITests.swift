import XCTest

final class DiscoveryNavigationUITests: XCTestCase {
  private var expectedCloudHome: String {
    ProcessInfo.processInfo.environment["ENERGYLENS_TEST_EXPECTED_HOME"] ?? "niksim"
  }

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
      .matching(NSPredicate(format: "label CONTAINS[c] %@", expectedCloudHome))
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
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Cloud home: \(expectedCloudHome)"))
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

  func testCloudSessionAutoPairsOwnedHubAndShowsSavedPlug() throws {
    continueAfterFailure = false
    guard
      ProcessInfo.processInfo.environment["ENERGYLENS_TEST_REUSE_SESSION"] == "1",
      ProcessInfo.processInfo.environment["ENERGYLENS_TEST_RESET_OWNED_PAIRING"] == "1",
      let username = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_USERNAME"],
      !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw XCTSkip("An existing Cloud session and the scoped owned-pairing reset were not enabled.")
    }

    let app = XCUIApplication(bundleIdentifier: "io.energylens.energylensMobile")
    addUIInterruptionMonitor(withDescription: "Local Network permission") { alert in
      guard alert.buttons["Allow"].exists else { return false }
      alert.buttons["Allow"].tap()
      return true
    }
    app.launchArguments = ["--energylens-reset-owned-hub-pairing"]
    app.launch()

    let usernameField = app.textFields["Username"]
    if usernameField.waitForExistence(timeout: 15) {
      guard let password = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_PASSWORD"],
            !password.isEmpty else {
        XCTFail("The Cloud session was absent and private sign-in credentials were not supplied")
        return
      }
      let passwordField = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label == %@", "Password"))
        .firstMatch
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
    XCTAssertEqual(XCTWaiter.wait(for: [routeReady], timeout: 180), .completed,
                   "The existing Cloud session did not restore a home")
    XCTAssertFalse(usernameField.exists, "The acceptance test did not reach an authenticated home")

    let demoHome = app.buttons
      .matching(NSPredicate(format: "label CONTAINS[c] %@", expectedCloudHome))
      .firstMatch
    if chooseHome.exists {
      let selectionRoute = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in demoHome.exists || settings.exists },
        object: app)
      XCTAssertEqual(XCTWaiter.wait(for: [selectionRoute], timeout: 60), .completed)
    }
    if demoHome.exists && !settings.exists { demoHome.tap() }
    XCTAssertTrue(settings.waitForExistence(timeout: 120))
    let settingsFrame = settings.frame
    app.coordinate(
      withNormalizedOffset: CGVector(
        dx: (settingsFrame.midX - app.frame.minX) / app.frame.width,
        dy: (settingsFrame.midY - app.frame.minY) / app.frame.height)).tap()

    let accountIdentity = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", username))
      .firstMatch
    XCTAssertTrue(accountIdentity.waitForExistence(timeout: 60),
                  "The reused Cloud session did not show the expected username in Profile")
    let selectedHome = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label ==[c] %@", expectedCloudHome))
      .firstMatch
    XCTAssertTrue(selectedHome.waitForExistence(timeout: 60),
                  "Profile did not show the selected Cloud home")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Account Owner"))
                    .firstMatch.waitForExistence(timeout: 60),
                  "Account Owner field was missing from Profile")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Zipcode (Tariff Zone)"))
                    .firstMatch.waitForExistence(timeout: 60),
                  "Zipcode field was missing from Profile")
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
                  "Auto Scan did not open the native discovery screen")
    XCTAssertFalse(app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Paste hub pairing JSON"))
      .firstMatch.exists, "Automatic owner pairing opened the operator JSON form")
    let connected = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Hub connected"))
      .firstMatch
    XCTAssertTrue(connected.waitForExistence(timeout: 120),
                  "The current owned Hub pairing did not connect automatically")

    if ProcessInfo.processInfo.environment["ENERGYLENS_TEST_REQUIRE_SAVED_PLUG"] == "0" {
      let evidence = XCTAttachment(screenshot: app.screenshot())
      evidence.name = "Owned Hub connected to selected Cloud home"
      evidence.lifetime = .keepAlways
      add(evidence)
      return
    }

    let saved = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Kitchen Mixer Plug"))
      .firstMatch
    for _ in 0..<5 {
      if saved.exists { break }
      app.swipeUp()
    }
    XCTAssertTrue(saved.waitForExistence(timeout: 90), "Saved KS8 plug was not visible")
    XCTAssertTrue(app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "KP115(US)"))
      .firstMatch.exists, "Saved plug model KP115(US) was not visible")
    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "Auto-paired owned Hub with saved KS8 plug"
    evidence.lifetime = .keepAlways
    add(evidence)

    let back = app.buttons["Back"]
    XCTAssertTrue(back.exists, "Discovery back navigation was unavailable")
    back.tap()
    XCTAssertTrue(app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Kitchen Mixer Plug"))
      .firstMatch.waitForExistence(timeout: 90),
      "Saved KS8 plug did not appear in the monitored devices list")
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
      .matching(NSPredicate(format: "label == %@", "Internal Error, Try again later"))
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
      .matching(NSPredicate(format: "label == %@", "Internal Error, Try again later"))
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
      predicate: NSPredicate { _, _ in
        chooseHome.exists || settings.exists || startupError.exists
      },
      object: app)
    let routeResult = XCTWaiter.wait(for: [routeReady], timeout: 300)
    XCTAssertFalse(startupError.exists, "Cloud sign-in reported a submission failure")
    XCTAssertEqual(routeResult, .completed, "Cloud sign-in did not reach a home or Settings")
    let chooserTileLabel = NSPredicate(
      format: "label CONTAINS[c] %@ AND label MATCHES[c] %@",
      expectedCloudHome,
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
    XCTAssertTrue(accountIdentity.waitForExistence(timeout: 60), "Signed-in username was not visible in Profile")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Account Owner"))
                    .firstMatch.waitForExistence(timeout: 60),
                  "Account Owner field was missing from Profile")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Zipcode (Tariff Zone)"))
                    .firstMatch.waitForExistence(timeout: 60),
                  "Zipcode field was missing from Profile")
    XCTAssertFalse(passwordField.exists, "Password field remained after sign-in")

    let profile = XCTAttachment(screenshot: app.screenshot())
    profile.name = "Cloud account profile"
    profile.lifetime = .keepAlways
    add(profile)

    // Acceptance setup may establish one legitimate local Cloud session for
    // later strict-reuse tests. The default path still exercises sign-out.
    if ProcessInfo.processInfo.environment["ENERGYLENS_TEST_PRESERVE_SESSION"] == "1" {
      app.terminate()
      app.launchArguments = []
      app.launch()
      XCTAssertTrue(settings.waitForExistence(timeout: 90),
                    "Cloud session did not survive a process relaunch")
      XCTAssertFalse(usernameField.exists,
                     "Cloud session returned to sign-in after a process relaunch")
      return
    }

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
    XCTAssertFalse(accountIdentity.exists, "Signed-in username remained visible after sign-out")
    let freshForm = XCTAttachment(screenshot: app.screenshot())
    freshForm.name = "Cloud sign-in after sign-out"
    freshForm.lifetime = .keepAlways
    add(freshForm)
  }

  func testCloudSessionShowsApprovedLampInDevices() throws {
    continueAfterFailure = false
    guard
      ProcessInfo.processInfo.environment["ENERGYLENS_TEST_REUSE_SESSION"] == "1",
      let username = ProcessInfo.processInfo.environment["ENERGYLENS_TEST_USERNAME"],
      !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw XCTSkip("An existing Cloud session and its account identity were not supplied.")
    }

    let app = XCUIApplication(bundleIdentifier: "io.energylens.energylensMobile")
    app.launch()

    func exactLabel(_ label: String) -> XCUIElement {
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    func capture(_ name: String) {
      let evidence = XCTAttachment(screenshot: app.screenshot())
      evidence.name = name
      evidence.lifetime = .keepAlways
      add(evidence)
    }
    func reveal(_ element: XCUIElement) {
      for _ in 0..<16 {
        if element.exists && element.isHittable { return }
        app.swipeUp()
      }
    }
    func tapNavigation(_ element: XCUIElement) {
      let frame = element.frame
      app.coordinate(withNormalizedOffset: CGVector(
        dx: (frame.midX - app.frame.minX) / app.frame.width,
        dy: (frame.midY - app.frame.minY) / app.frame.height)).tap()
    }

    let settings = app.links
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings"))
      .firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 180), "Authenticated dashboard did not render")
    capture("Cloud authenticated cold-launch dashboard")
    tapNavigation(settings)
    XCTAssertTrue(exactLabel(username).waitForExistence(timeout: 90),
                  "Reused Cloud session did not belong to the approved account")

    let manageDevices = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", "Manage Devices"))
      .firstMatch
    XCTAssertTrue(manageDevices.waitForExistence(timeout: 60))
    manageDevices.tap()

    let lampName = "Philips Hue two-bulb lamp"
    let savedLamp = exactLabel(lampName)
    XCTAssertTrue(savedLamp.waitForExistence(timeout: 90),
                  "Cloud appliance was absent from Manage Devices")
    reveal(savedLamp)
    XCTAssertTrue(savedLamp.isHittable, "Cloud appliance was outside the visible inventory")
    // Only persisted Cloud appliances receive this control; never activate it.
    XCTAssertTrue(app.buttons["Remove " + lampName].exists,
                  "Lamp did not render as a persisted Cloud appliance")
    capture("Cloud approved lamp in Manage Devices")

    let devices = app.links.matching(NSPredicate(
      format: "label CONTAINS[c] %@ AND NOT (label CONTAINS[c] %@)",
      "Devices", "Manage")).firstMatch
    XCTAssertTrue(devices.waitForExistence(timeout: 30), "Devices navigation was unavailable")
    tapNavigation(devices)
    XCTAssertTrue(exactLabel("MONITORED DEVICES").waitForExistence(timeout: 60),
                  "Devices energy page did not finish navigating")
    let deviceLamp = exactLabel(lampName)
    XCTAssertTrue(deviceLamp.waitForExistence(timeout: 90),
                  "Cloud appliance was absent from the Devices energy page")
    reveal(deviceLamp)
    XCTAssertTrue(deviceLamp.isHittable, "Cloud appliance card was outside the visible device list")
    capture("Cloud approved lamp on Devices energy page")
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
    let settingsFrame = settings.frame
    let settingsCenter = app.coordinate(
      withNormalizedOffset: CGVector(
        dx: (settingsFrame.midX - app.frame.minX) / app.frame.width,
        dy: (settingsFrame.midY - app.frame.minY) / app.frame.height))
    settingsCenter.tap()

    let manageDevices = labeled("Manage Devices")
    XCTAssertTrue(manageDevices.waitForExistence(timeout: 30), "Manage Devices did not render")
    manageDevices.tap()

    let autoScan = labeled("Auto Scan")
    XCTAssertTrue(autoScan.waitForExistence(timeout: 30), "Auto Scan did not render")
    autoScan.tap()

    XCTAssertTrue(labeled("Find a smart plug").waitForExistence(timeout: 30))
    let results = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        labeled("Detected plugs").exists || labeled("Nearby devices").exists
      },
      object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [results], timeout: 30), .completed)
  }
}
