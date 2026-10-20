# EnergyLens Mobile

Flutter app (package `energylens_mobile`) showing household and device electricity cost/waste. Customer UI is 14 owner-approved HTML pages rendered in a WebView, bridged to Dart (hub client, Cloud client, auth, photo identification). Setup, profiles and auth flows: [README.md](README.md). Product/design rules: [PRODUCT.md](PRODUCT.md), [DESIGN.md](DESIGN.md); earlier record in `../energylens-common/product/mobile/`.

## Stack
- Flutter 3.47.4 stable / Dart 3.13.3 (`sdk: ^3.13.3`). No router or state-management package: `MaterialApp` + `Navigator.push`, `StatefulWidget`/`setState`.
- Plugins: `flutter_secure_storage`, `flutter_appauth`, `webview_flutter`, `url_launcher`, `image_picker`, `google_mlkit_text_recognition`, `mobile_scanner`, `path_provider`; plus `http`, `crypto`, `image`, `timezone`.
- iOS: bundle `io.energylens.energylensMobile`, deployment target 15.5 (ML Kit), URL scheme `io.energylens.app`.
- Android: `applicationId`/namespace `io.energylens.energylens_mobile`, AGP 9.1.0, Kotlin plugin 2.4.0, Gradle 9.3.1, Java/JVM 17, minSdk 24 / target+compile 36 (Flutter defaults, read from built APK).

## Layout
- `lib/main.dart`: `EnergyLensApp`. `ENERGYLENS_LOCAL_PILOT=true` -> `DesignShell(localPilot)`; otherwise `CloudEntryGate` -> `DesignShell`.
- `lib/features/design/`: `design_shell.dart` loads `assets/design_pages/<page>/app.html` via `loadFlutterAsset`, injects data with `runJavaScript*`, receives events on JS channels (`EnergyLensNavigation`, `...DeviceReview`, `...PhotoCapture`, `...DeleteDevice`, `...Knowledge`). Domain repositories/adapters/renderers per page.
- `lib/core/cloud_auth/`: config (`cloud_auth.dart`), OIDC via AppAuth, first-party username/email auth (`cloud_local_auth.dart`), dev TLS pin (`cloud_dev_tls.dart`), entry gate, registration/recovery.
- `lib/core/cloud_api/`: Cloud `/v1` client (`/me`, `/homes`, `/hubs`, `/energy`, `/catalog`, `/usage-facts`, `/auth`) and DTOs.
- `lib/features/discovery/`: hub HTTPS client (`discovery_api.dart`, hub `/v1` + `/v2` routes), pairing (`hub_pairing_screen.dart`, QR via `mobile_scanner`), stored credentials (`discovery_credentials.dart`). Plug discovery runs on the hub (scan API); the app does no mDNS/multicast.
- `lib/features/identify/`: appliance onboarding, photo capture (`image_picker`), OCR (ML Kit), UPC (`mobile_scanner.analyzeImage`).
- `lib/features/energy/`: Cloud energy screens, Stop Waste programs (`local_pilot_programs.dart`).
- `assets/design_pages/`: 14 pages; `app.html` is shipped, `code.html`/`screen.png` are byte-for-byte references. `shared/` holds chrome.js, CSS, bundled fonts.
- `test/`: unit/widget tests mirroring `lib/`; `test/goldens/design_shell/` iOS simulator baseline (see its README). `tool/`: `design_visual_goldens.py` (iOS simulator capture/compare), `mark_design_bindings.py`.
- `docs/`: binding-ID map (`design_page_binding_map.*`), copy inventory (`new-ui-copy-review.md`).
- `scripts/deploy-ios-simulator.sh` (iOS) and `scripts/deploy-android.sh` (Android): deploy scripts. `scripts/android-smoke.sh`: Android launch/rotation/cold-restart/logcat check.

## Build profiles and dart-defines
All are compile-time `--dart-define`s. Template: `.env-example` -> `.env-local` (chmod 600, gitignored).

| Define | Read at | Meaning |
|---|---|---|
| `ENERGYLENS_LOCAL_PILOT` | main.dart:21 | `true`: account-free pilot shell. |
| `ENERGYLENS_DESIGN_TOUR` | main.dart:102 | Auto-advance the 14 pages (pilot only). |
| `ENERGYLENS_DESIGN_TOUR_DWELL_SECONDS` | design_shell.dart:281 | Tour dwell, default 8. |
| `ENERGYLENS_HUB_URL` | discovery_credentials.dart:18 | Fallback hub `https://<private IPv4>:PORT[#sha256=<64 hex>]`. |
| `ENERGYLENS_CLOUD_API_URL` | cloud_auth.dart:28 | HTTPS origin, no path/query/fragment. |
| `ENERGYLENS_CLOUD_LOCAL_AUTH_ENABLED` | cloud_auth.dart:29 | First-party username/email auth. |
| `ENERGYLENS_CLOUD_DEV_AUTH_ENABLED` + `ENERGYLENS_APP_ENV=dev` | cloud_auth.dart:32-33 | Dev auth; required for the dev cert pin. |
| `ENERGYLENS_CLOUD_DEV_CERT_SHA256` | cloud_auth.dart:34 | Cloud leaf DER SHA-256; throws unless dev auth is configured. |
| `ENERGYLENS_CLOUD_LOCAL_AUTH_LINK_ORIGIN` | cloud_auth.dart:37 | Origin allowed for pasted verify/reset links. |
| `ENERGYLENS_OIDC_ISSUER`/`_AUDIENCE`/`_CLIENT_ID`/`_REDIRECT_URL` | cloud_auth.dart:24-27 | OIDC; redirect must be `io.energylens.app://login-callback`. |

- `ENERGYLENS_POSTAL_CODE` is passed by the deploy script but no Dart code reads it.
- `ENERGYLENS_HUB_TOKEN` is never compiled in; the iOS script hands it over at runtime (see Gotchas).
- Profiles: local pilot (`LOCAL_PILOT=true`); Hub pilot (`LOCAL_PILOT=false` + `HUB_URL`); Cloud OIDC (4 OIDC defines + API URL); local username auth or email auth (`CLOUD_LOCAL_AUTH_ENABLED=true` + API URL). Debug builds with no Cloud config show a `LOCAL PREVIEW` path (`allowLocalPreview`, kDebugMode only).

## Commands (verified 2026-10-20 on Linux unless marked)
```sh
flutter pub get
flutter analyze          # exits 1: 38 info/warning issues (pre-existing lints; unused local in test/features/energy/cloud_report_preview_screen_test.dart:235)
flutter test             # 820 pass, 1 skip (needs Chrome); needs the sibling checkouts
flutter build apk --debug --dart-define=ENERGYLENS_LOCAL_PILOT=true   # OK, build/app/outputs/flutter-apk/app-debug.apk
```
- Single file: `flutter test test/features/discovery/pairing_test.dart`. Test run takes ~25 s; debug APK build ~2.5 min cold.
- Debug APK is ~222 MB (arm64-v8a, armeabi-v7a, x86_64). `flutter doctor` reports some Android licenses unaccepted; the build still succeeds.
- Release builds minify with R8; rules are in `android/app/proguard-rules.pro` (ML Kit script-specific recognizers are `-dontwarn`).
- iOS (macOS only, not run here): `scripts/deploy-ios-simulator.sh --local-pilot --device UDID`, `--cloud --device UDID`, `--hub-url 'https://IP:PORT#sha256=HEX' --device UDID`, `--iphone UDID` (signed Release), `--build-only`, `--env-file PATH`, `--team ID`. Wrapper: `../energylens-dev-bash-scripts/deploy-ios.sh`.
- Android: `scripts/deploy-android.sh --cloud|--local-pilot|--hub-url URL` with `--emulator AVD_OR_SERIAL`, `--physical SERIAL`, `--release`, `--reverse PORT`, `--env-file PATH`, `--build-only`; wrapper `../energylens-dev-bash-scripts/deploy-android.sh`. `scripts/android-smoke.sh --serial S --out DIR` checks an installed app.
- Android AVDs `energylens-phone` and `energylens-tablet` (API 35, google_apis x86_64); SDK `~/tools/android-sdk`, JDK 17 at `~/tools/jdk-17`. Run one emulator at a time, with `-gpu swiftshader_indirect`.

## Conventions
- Demo app: mock/simulated devices and data are fine and may mix with real ones. Never mock a real device's real useful power usage.
- No UI change (layout, copy, styling, content) without owner approval; the 14 page designs are owner-approved. Edit `app.html` only, never `code.html`/`screen.png`.
- Release builds require real configured authentication; local/dummy auth stays in debug or local configuration.
- Hub addresses must be HTTPS private IPv4 (10/8, 100.64/10, 172.16/12, 192.168/16, 127.0.0.1); pairing requires a `#sha256=` pin.
- Credentials live only in `flutter_secure_storage`; Cloud keys are prefixed `energylens.cloud.`, hub keys `energylens.hub.`.
- Backend/internal failures (5xx, network, timeout, unparseable) show only `internalErrorMessage` (`lib/core/backend_error.dart`); Cloud 401/403 sign the user out through `CloudApiClient.onSessionRejected`. No technical detail reaches the UI.
- Commit messages: Conventional Commits.

## Cross-repo
- `../energylens-hub`: hub HTTPS API used by `discovery_api.dart`.
- `../energylens-cloud`: Cloud `/v1` API and auth; run locally via `../energylens-dev-bash-scripts/run-energylens-cloud.sh` (see that README).
- `../energylens-common-contracts`: `test/features/discovery/nearby_discovery_test.dart` reads `api/testdata/protocol-v2-hub-routes.json` from it; that test needs the sibling checkout.
- `../energylens-common`: product docs; `tool/mark_design_bindings.py` reads `docs/plans/support/golden_fixtures`.
- `../energylens-web` uses overlapping Cloud routes with a different design system.

## Gotchas
- Hub and dev-Cloud pinning is pure Dart: `HttpClient(SecurityContext(withTrustedRoots: false))` + `badCertificateCallback` comparing SHA-256 of `certificate.der` (discovery_api.dart:112-125, 1686-1699; cloud_dev_tls.dart). It bypasses the Android network security config and iOS ATS.
- Hub-token handoff: the iOS script writes `{address, token}` to `<app data>/tmp/energylens-pairing.json`; `importDebugPairingFile` reads `Directory.systemTemp` only when `kDebugMode && Platform.isIOS` (discovery_credentials.dart:21), so it does nothing on Android.
- `--energylens-reset-sign-in` is handled natively in `ios/Runner/AppDelegate.swift` (CommandLine.arguments). Android `MainActivity.kt` is a bare `FlutterActivity` with no equivalent.
- iOS simulator builds are x86_64 only (ML Kit pods); Apple Silicon needs Rosetta.
- Android release builds are signed with the debug key (`android/app/build.gradle.kts`); physical devices get Release builds only. The app label is `EnergyLens` (`AndroidManifest.xml`). Launcher icons on both platforms are Flutter defaults.
- The HTML pages target 390-430px phone portrait. Tablet layout is `assets/design_pages/shared/tablet_layout.css`, loaded by `shared/chrome.js`, active at `(min-width: 700px) and (min-device-width: 600px) and (min-device-height: 600px) and (min-height: 320px)`. Native Flutter screens cap content width at 420-680px.
- `webview_flutter` returns `runJavaScriptReturningResult` values differently per platform; `_capturePageState` handles JSON-encoded strings, and the `installed != true` checks assume a bool.
