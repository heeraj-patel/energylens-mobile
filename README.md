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

## Cloud sign-in build configuration

Release builds require these `--dart-define` values: `ENERGYLENS_OIDC_ISSUER`
(HTTPS), `ENERGYLENS_OIDC_AUDIENCE`, `ENERGYLENS_OIDC_CLIENT_ID`,
`ENERGYLENS_OIDC_REDIRECT_URL=io.energylens.app://login-callback`, and
`ENERGYLENS_CLOUD_API_URL` (HTTPS origin). Register that callback with the OIDC
provider's public mobile client. The app uses authorization code with PKCE and
requests `offline_access`; it never embeds a client secret. A release build with
missing or invalid settings stays at the configuration screen. Debug builds
without settings can preview local hub features and display a `LOCAL PREVIEW`
banner; that path is compiled out of release builds.

After token exchange, the app requires a verified account from authenticated
`GET /v1/me`, then loads owned cloud homes from `GET /v1/homes`. Users can
select an existing home or create one with a name, ZIP/postal code, country,
and IANA time zone. Creation uses `POST /v1/homes` with a UUID idempotency key;
an unchanged retry after an uncertain response reuses the key. Cloud errors do
not open local Home. The selected cloud home is labeled in Home, while local
hub devices remain separate until claim and sync trust routes are verified.
The cloud account and home routes must be live before a configured build can
complete this entry flow. Cloud bearer tokens are stored
separately from the existing local hub pairing credentials. Sign-out clears only
cloud tokens; local hub TLS and pairing continue to use their existing trust path.

## First-party email authentication (default off)

Build with `ENERGYLENS_CLOUD_LOCAL_AUTH_ENABLED=true` and a real HTTPS
`ENERGYLENS_CLOUD_API_URL` to display email registration and sign-in. This is
independent of OIDC build settings; when both are configured, OIDC sign-in
remains available. The Cloud server must separately enable and configure its
guarded local-auth routes and verification mail. A server with the gate off
returns 404 and the app shows that email authentication is unavailable. A
registration request never signs the user in; verification and a separate
login are required. Local access and refresh tokens use secure storage and
the Cloud API bearer path. The local photo pilot remains a separate build mode.

## iOS simulator pilot

The self-contained `scripts/deploy-ios-simulator.sh` adapts the explicit-target
build and deploy workflow from `kernel-app/scripts/run-kernel-app.sh`. It passes
the hub IPv4 address at build time, installs the app, and launches it. Use an
HTTPS address whose certificate includes the address in its subject alternative
names. For a self-signed certificate, append `#sha256=` and the 64 lowercase
hexadecimal digits of the leaf certificate's DER SHA-256 digest. Verify that
fingerprint through a trusted channel before pairing. The pilot
token is supplied through `ENERGYLENS_HUB_TOKEN`, passed via a temporary file
in the simulator app container, and stored in the simulator's Keychain. The
app deletes the temporary file after reading it. It is not compiled into the
app. For example:

```sh
HUB_CERT_SHA256="$(openssl x509 -in /secure/path/to/hub.crt -outform DER | openssl dgst -sha256 | awk '{print $NF}')"
ENERGYLENS_HUB_TOKEN="$(tailscale ssh nipatel@nipatel-solvzoom 'sed -n "s/^ENERGYLENS_DISCOVERY_TOKEN=//p" "$HOME/energylens-pilot/hub.env"')" \
  scripts/deploy-ios-simulator.sh --hub-url "https://192.168.68.136:18787#sha256=$HUB_CERT_SHA256" \
  --postal-code 78732 \
  --device 16A0C929-143E-494A-9BC7-546F39A0D3A7
```

The simulator must be booted. The current ML Kit iOS simulator dependencies
produce an Intel binary, so Apple Silicon Macs need Rosetta 2 to launch it.
