# EnergyLens Mobile

This Flutter app shows home and device energy and cost information on iOS and Android.
It supports Cloud sign-in, owned Hub discovery, device setup, and local pilot previews.
Device readings and estimates are shown through their configured data sources.

## Setup for development, testing, building, and deployment

Install Flutter, Xcode and CocoaPods for iOS, or the Android SDK for Android. Run `flutter pub get`. Copy `.env-example` to a private mode-`0600` `.env-local`, or select another profile with `--env-file`. Keep passwords and server secrets out of Mobile profiles. Follow the [owner topology and certificate preflight](../energylens-dev-bash-scripts/MOBILE_IOS_OPERATIONS.md#mobile-owner-topology-and-source-of-truth) for Cloud builds; detailed [Mobile operations](ENGINEERING_REFERENCE.md) cover profile flags and native acceptance.

To show Auto-scan hub connection diagnostics, build with `--dart-define=DEVELOPER_MODE=TRUE`, for example `flutter run --dart-define=DEVELOPER_MODE=TRUE`. The define is compiled into the app; rebuild to change it.

## Build commands and scripts

```sh
flutter pub get
flutter build ios --release --dart-define=ENERGYLENS_LOCAL_PILOT=true
scripts/deploy-ios-simulator.sh --cloud --env-file /private/path/mobile.env --device SIMULATOR_UDID --build-only
```

Use the configured Cloud local-auth flags and HTTPS origin for a Cloud profile. `scripts/deploy-ios-simulator.sh` also accepts `--local-pilot` and Android uses `scripts/deploy-android.sh`.

## Test commands and scripts

```sh
flutter test
```

Before each physical iPhone build, install, or test, complete a current simulator build and relevant native Home/Hub UI test. The [iOS test commands](../energylens-dev-bash-scripts/MOBILE_IOS_OPERATIONS.md#mobile-flutter-ios) describe the `xcodebuild` sequence and private test-run configuration.

## Deployment commands and scripts

```sh
scripts/deploy-ios-simulator.sh --local-pilot --device <SIMULATOR_UDID>
scripts/deploy-ios-simulator.sh --cloud --env-file /private/path/mobile.env --device <SIMULATOR_UDID>
scripts/deploy-ios-simulator.sh --cloud --env-file /private/path/mobile.env --iphone PHYSICAL_DEVICE_UDID
scripts/deploy-android.sh --cloud --emulator energylens-phone
```

The physical iPhone path requires a signed Release build and the simulator precheck. Rebuild after changing the Cloud URL, authentication flags, or certificate pin.

## Troubleshooting

If sign-in fails before credentials, check the compiled Cloud origin, `/v1/auth/config`, certificate trust, and matching pin. Reinstall after correcting build settings; an installed app retains its prior compiled profile. Inspect the selected profile without printing credentials.
