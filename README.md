# EnergyLens Mobile

Flutter mobile app for Android and iOS. The initial screen clearly shows the disconnected state; it does not display simulated electricity readings as measurements.

## Reused code

Copied and adapted from `../kernel-app` at commit `f767a88400fbde92ffda16e5c41656cd5349f963`:

- `lib/core/api/energy_models.dart` — energy estimate and rate DTOs
- `lib/features/energy_estimate/logic/energy_estimate_calculator.dart` — local calculator for an estimate slider
- the calculator test and fixture in `test/features/energy_estimate/`

The calculator works with estimated device usage and is not a substitute for measured energy or intervention savings. Kernel's account, onboarding, health, vault, and Sage screens were not copied. This repo still needs an EnergyLens hub API client and the monitored-computer flow.

```sh
flutter test
flutter run
```
