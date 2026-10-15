import XCTest

final class DiscoveryNavigationUITests: XCTestCase {
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
