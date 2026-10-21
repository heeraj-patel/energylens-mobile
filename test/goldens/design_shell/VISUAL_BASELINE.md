# iOS simulator visual baseline

`iphone16pro_ios18_6_light/` contains 14 first-viewport screenshots of the approved static DesignShell pages. The manifest pins the simulator, light appearance, fixed status bar, page order, packaged HTML hashes, app executable hash, and PNG hashes. These images are a baseline for later visual comparisons; they do not establish backend binding, below-fold coverage, interaction behavior, or physical iPhone acceptance.

Build the simulator-only local pilot with the design tour enabled:

```sh
flutter build ios --simulator --debug \
  --dart-define=ENERGYLENS_LOCAL_PILOT=true \
  --dart-define=ENERGYLENS_DESIGN_TOUR=true
```

Use a booted iPhone 16 Pro simulator running iOS 18.6. Find its UDID with `xcrun simctl list devices booted`, then capture into a temporary directory and compare:

```sh
python3 tool/design_visual_goldens.py capture --device <SIMULATOR_UDID> --out /tmp/energylens-design-actual
python3 tool/design_visual_goldens.py compare \
  --baseline test/goldens/design_shell/iphone16pro_ios18_6_light \
  --actual /tmp/energylens-design-actual
```

Capture waits for a visible, page-specific marker and fails if any screen is blank or mislabeled. Comparison checks baseline and actual capture integrity, current packaged HTML against the actual capture, image dimensions, and changed-pixel fraction. This allows a markup refactor to prove visual parity against the older baseline. The default allowed fraction is 0.5%; set `--max-changed-fraction 0` for exact pixel parity. Investigate every failure before updating the baseline. Review screenshots visually when changing the app, simulator, iOS version, or font assets; create a new versioned directory for a changed device or OS.
