# Mobile agent guidance

Follow the workspace `../AGENTS.md`, especially Mobile-first UI priority, exact customer-copy approval, and simulator preflight for physical iPhone work.

- The Flutter app's customer pages are packaged DesignShell HTML under `assets/design_pages/`, bridged to Dart for Cloud, Hub, authentication, and device identification. Read `PRODUCT.md`, `DESIGN.md`, and the canonical `../energylens-common/product/mobile/` guidance before changing UI.
- Only edit customer-facing layout or copy after the owner approves the exact text and placement. Preserve provenance so demo values are never presented as measurements.
- A Mobile build profile selects Cloud origin, authentication mode, and development certificate pin at compile time. Keep passwords out of profiles. Rebuild and reinstall after profile changes; an installed app retains the previous values.
- For a shared home, verify the selected profile's HTTPS origin and pin, then the current authenticated Cloud home and owned-Hub connection hint. Do not rely on saved pairing state alone.
- Run `flutter test` and the relevant native simulator Home/Hub UI test before a signed Release iPhone action, following `../energylens-dev-bash-scripts/MOBILE_IOS_OPERATIONS.md`.
- `test/goldens/design_shell/VISUAL_BASELINE.md` explains the static visual baseline; it does not establish live API or physical device acceptance.
