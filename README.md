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

## Repository-local configuration

Copy `.env-example` to `.env-local`, fill in the settings for the intended
profile, and run `chmod 600 .env-local`. The local file is ignored by Git.
`scripts/deploy-ios-simulator.sh` loads it automatically; `--env-file PATH`
selects another file. Public build settings are passed to Flutter; account
passwords and server secrets belong in server configuration and are never
compiled into Mobile.

Use `--local-pilot` for the account-free preview. To use sign-in and sign-out,
configure the HTTPS Cloud API and its authentication profile, then run:

```sh
scripts/deploy-ios-simulator.sh --cloud --device SIMULATOR_UDID
```

For owner-requested physical acceptance, replace `--device SIMULATOR_UDID`
with `--iphone PHYSICAL_DEVICE_UDID`; this uses the existing signed Release
workflow. The Cloud API and certificate trust must be reachable on that device.
Add `--build-only` to prepare and verify the selected build without installing.
For a direct Flutter launch, export the file first and pass the public settings
as `--dart-define` values using the profile instructions below.

To force a fresh Cloud sign-in after reinstall, launch the installed app once
with `--energylens-reset-sign-in`. This one-shot startup option deletes only
Flutter secure-storage Keychain entries whose account starts with
`energylens.cloud.`; it preserves Hub pairing and unrelated Keychain entries.
On a connected iPhone, use:

```sh
xcrun devicectl device process launch --terminate-existing --device PHYSICAL_DEVICE_UDID io.energylens.energylensMobile --energylens-reset-sign-in
```

Confirm the launch log reports that the reset completed. Reinstalling alone
does not clear iOS Keychain credentials; the app then starts normally and
requires Cloud sign-in again.

## Cloud sign-in build configuration

Stop Waste loads household and appliance-matching programs from the Cloud
home-level program endpoint. It displays only offers whose availability is
`open` and whose review expiry is still in the future.
The section heading remains visible when the feed has no qualifying rows or a
Cloud home is unavailable. Each offer shows its category, supplied title and
benefit, administrator name, and source URL; tapping it opens the source in the
phone's default browser. The detailed per-appliance discovery screen remains
in code for diagnostics and is not linked from customer navigation.

`ENERGYLENS_LOCAL_PILOT` builds show one staged DOE Weatherization Assistance
Program source card on the local Hub Stop Waste screen while its October 12,
2026 review is current. This fallback is confined to local pilot mode and is
never merged into the Cloud home feed. Its immutable source hash and expiry
are recorded in `lib/features/energy/local_pilot_programs.dart`.

For OIDC sign-in, Release builds require these `--dart-define` values: `ENERGYLENS_OIDC_ISSUER`
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
complete this entry flow. Cloud bearer tokens and Hub pairing credentials use
separate secure records. Sign-out clears the active Cloud session and detaches
authenticated Hub access. Pairing restored for a Cloud home must match its
verified account, home, Hub and ownership epoch; legacy local-pilot pairing
does not authorize an authenticated home.

## Local username authentication

Start the Cloud API with `RUNTIME_ENV=local` using the
[existing local launcher and private configuration](../energylens-dev-bash-scripts/README.md).
For the authenticated Mobile build, set `ENERGYLENS_LOCAL_PILOT=false`,
`ENERGYLENS_CLOUD_LOCAL_AUTH_ENABLED=true`, and the configured HTTPS
`ENERGYLENS_CLOUD_API_URL` through `--dart-define`. Trust the configured server
certificate on the intended client; do not disable TLS verification. OIDC and
email-link settings are unnecessary for this profile.

The API's `/v1/auth/config` must advertise username authentication. Registration
then signs in and verifies `/v1/me`; username accounts do not need email
verification. Accept the existing disclosure explicitly, then create or select
an owned home. Pending home creation retains its idempotency key across an
uncertain response or restart. Changing home keeps the login and replaces the
home context; signing into another account loads only that account's homes.
If capability loading fails, check API reachability, certificate trust and
server runtime configuration before retrying.

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
Set `ENERGYLENS_CLOUD_LOCAL_AUTH_LINK_ORIGIN` to the exact HTTPS origin used by
the Cloud verification and reset emails to allow pasting their links. The app
accepts only the expected verification or reset path at that origin, extracts
the one-use token from the URL fragment, and clears the copied link from the
clipboard. A bare 43-character token can also be pasted. Password recovery
requests have generic acceptance and require a separate one-use reset link;
they do not sign the user in.

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

For the local pilot without a Hub URL, use the same deployment script through
the dev-bash-scripts entry point. A simulator gets an Xcode Debug build; a
paired iPhone gets a signed Xcode Release build. Both use
`ENERGYLENS_LOCAL_PILOT=true`, and the iPhone install runs over Xcode's device
connection. Use a physical iPhone only for owner-requested acceptance.

```sh
cd ../energylens-dev-bash-scripts
./deploy-ios.sh --local-pilot --device SIMULATOR_UDID
./deploy-ios.sh --local-pilot --iphone PHYSICAL_DEVICE_UDID
```

Pass both targets in one command to install on both after their respective
builds. See the [deployment guide](../energylens-dev-bash-scripts/README.md)
for signing, wireless recovery, and the direct install command.

## Native owned-Hub auto-pair acceptance

The `RunnerUITests/DiscoveryNavigationUITests/testCloudSessionAutoPairsOwnedHubAndShowsSavedPlug`
test verifies automatic pairing for an existing Cloud session, then checks that
the Kitchen Mixer Plug KS8 (`KP115(US)`) appears in Auto Scan and the monitored
device list. It does not sign in or accept operator pairing JSON. Set
`ENERGYLENS_TEST_REUSE_SESSION=1`,
`ENERGYLENS_TEST_RESET_OWNED_PAIRING=1`, and
`ENERGYLENS_TEST_USERNAME` only in the private `RunnerUITests` environment of
a temporary `.xctestrun` copy. This test does not need a password. Keep the
temporary test-run file mode 0600 and remove it after the run.

The reset flag clears only Keychain accounts with the
`energylens.hub.pairing.v2.` prefix, including their scoped client IDs. It
preserves the Cloud login, legacy pairing records, and unrelated secure
storage. The test skips unless both explicit test flags are enabled, then
launches with `--energylens-reset-owned-hub-pairing`.
