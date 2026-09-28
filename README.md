# EnergyLens Mobile

Flutter mobile app for Android and iOS. The initial screen clearly shows the disconnected state; it does not display simulated electricity readings as measurements.

## Reused code

Copied and adapted from `../kernel-app` at commit `f767a88400fbde92ffda16e5c41656cd5349f963`:

- `lib/core/api/energy_models.dart` — energy estimate and rate DTOs
- `lib/features/energy_estimate/logic/energy_estimate_calculator.dart` — local calculator for an estimate slider
- the calculator test and fixture in `test/features/energy_estimate/`

The calculator works with estimated device usage and is not a substitute for measured energy or intervention savings. Kernel's account, onboarding, health, vault, and Sage screens were not copied. EnergyLens now has its own hub client, plug discovery, manual appliance entry, and local photo identification; the monitored-computer flow remains future work.

```sh
flutter test
flutter run
```

## iOS simulator pilot

The self-contained `scripts/deploy-ios-simulator.sh` adapts the explicit-target
build and deploy workflow from `kernel-app/scripts/run-kernel-app.sh`. It passes
the hub IPv4 address at build time, installs the app, and launches it. For the
Geekom on the same LAN, use `http://192.168.68.136:18787`; if the Mac can only
reach the hub through Tailscale, use `http://100.115.133.73:18787`. The pilot
token is supplied through `ENERGYLENS_HUB_TOKEN`, passed via a temporary file
in the simulator app container, and stored in the simulator's Keychain. The
app deletes the temporary file after reading it. It is not compiled into the
app. For example:

```sh
ENERGYLENS_HUB_TOKEN="$(tailscale ssh nipatel@nipatel-solvzoom 'sed -n "s/^ENERGYLENS_DISCOVERY_TOKEN=//p" "$HOME/energylens-pilot/hub.env"')" \
  scripts/deploy-ios-simulator.sh --hub-url http://192.168.68.136:18787 \
  --postal-code 78732 \
  --device 16A0C929-143E-494A-9BC7-546F39A0D3A7
```

The simulator must be booted. The current ML Kit iOS simulator dependencies
produce an Intel binary, so Apple Silicon Macs need Rosetta 2 to launch it.
