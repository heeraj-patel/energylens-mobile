import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if CommandLine.arguments.contains("--energylens-reset-sign-in") {
      do {
        let deleted = try Self.clearCloudSignInKeychainItems()
        NSLog("EnergyLens one-shot sign-in reset completed; removed %d Cloud credential entries.", deleted)
      } catch {
        NSLog("EnergyLens one-shot sign-in reset failed; stopping launch: %@", String(describing: error))
        return false
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func clearCloudSignInKeychainItems() throws -> Int {
    let service = "flutter_secure_storage_service"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    let items = result as? [[String: Any]] ?? []
    var deleted = 0
    for item in items {
      guard let account = item[kSecAttrAccount as String] as? String,
            account.hasPrefix("energylens.cloud.") else {
        continue
      }
      let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
      guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(deleteStatus))
      }
      if deleteStatus == errSecSuccess {
        deleted += 1
      }
    }
    return deleted
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
