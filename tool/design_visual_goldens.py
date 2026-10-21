#!/usr/bin/env python3
"""Capture and compare the approved static DesignShell on an iOS simulator.

Capture requires a simulator build with ENERGYLENS_LOCAL_PILOT=true and
ENERGYLENS_DESIGN_TOUR=true. It does not install on a physical iPhone.
"""

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "io.energylens.energylensMobile"
PAGES = (
    "dashboard", "devices", "efficiency", "efficiency_away",
    "efficiency_habits", "efficiency_peak_rates", "perks_tips", "settings",
    "settings_manage_devices", "settings_manual_device_entry",
    "settings_photo_scan_onboarding", "tips_care_upgrades",
    "tips_efficiency", "tips_knowledge",
)
PAGE_MARKERS = {
    "dashboard": "Useful cost",
    "devices": "MONITORED DEVICES",
    "efficiency": "Monthly Overview",
    "efficiency_away": "While You're Away",
    "efficiency_habits": "Everyday Habits & Routine Diagnoses",
    "efficiency_peak_rates": "Peak Pricing Windows",
    "perks_tips": "DISCOVER SAVINGS",
    "settings": "Profile, device setup",
    "settings_manage_devices": "Add New Equipment",
    "settings_manual_device_entry": "Manual Device Entry",
    "settings_photo_scan_onboarding": "Take Photo",
    "tips_care_upgrades": "Care & Maintenance",
    "tips_efficiency": "Efficient Usage",
    "tips_knowledge": "Find Answers",
}

OCR_SOURCE = r'''import AppKit
import Vision
func openImage(_ path: String) -> NSBitmapImageRep? {
  guard let image = NSImage(contentsOfFile: path),
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
  return NSBitmapImageRep(cgImage: cg)
}
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--diff" {
  guard let a = openImage(CommandLine.arguments[2]), let b = openImage(CommandLine.arguments[3]),
        a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
        a.bitsPerPixel == b.bitsPerPixel else {
    fputs("image dimensions or formats differ\\n", stderr); exit(3)
  }
  let bytesPerPixel = a.bitsPerPixel / 8
  let aData = a.bitmapData!, bData = b.bitmapData!
  // Simulator system chrome can render the Dynamic Island differently between
  // captures. Compare the app viewport while still validating page text below.
  let appTop = Int(Double(a.pixelsHigh) * 0.07)
  var changed = 0
  for y in appTop..<a.pixelsHigh {
    for x in 0..<a.pixelsWide {
      let ai = y * a.bytesPerRow + x * bytesPerPixel
      let bi = y * b.bytesPerRow + x * bytesPerPixel
      if !((0..<bytesPerPixel).allSatisfy({ aData[ai + $0] == bData[bi + $0] })) { changed += 1 }
    }
  }
  print(Double(changed) / Double(a.pixelsWide * (a.pixelsHigh - appTop)))
  exit(0)
}
guard CommandLine.arguments.count == 2, let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  fputs("could not decode screenshot\\n", stderr); exit(2)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .fast
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cg).perform([request])
for result in request.results ?? [] {
  if let text = result.topCandidates(1).first?.string { print(text) }
}
'''


def build_ocr() -> Path:
    temp = Path(tempfile.mkdtemp(prefix="energylens-golden-ocr-"))
    source, binary = temp / "ocr.swift", temp / "ocr"
    source.write_text(OCR_SOURCE)
    subprocess.run(("swiftc", str(source), "-o", str(binary)), check=True)
    return binary


def visible_text(ocr: Path, image: Path) -> str:
    result = subprocess.run((str(ocr), str(image)), capture_output=True, text=True)
    if result.returncode:
        detail = result.stderr.strip() or f"OCR exited {result.returncode}"
        raise SystemExit(f"OCR failed for {image.name}: {detail}")
    return " ".join(result.stdout.split()).casefold()


def validate_label(ocr: Path, image: Path, page: str) -> None:
    marker = PAGE_MARKERS[page].casefold()
    text = visible_text(ocr, image)
    if marker not in text:
        raise SystemExit(f"{image.name}: expected visible label {PAGE_MARKERS[page]!r} for {page}")


def run(*args: str, check: bool = True) -> None:
    subprocess.run(args, check=check, stdout=subprocess.DEVNULL)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def filename(index: int, page: str) -> str:
    return f"{index:02d}-{page}.png"


def capture(device: str, output: Path, app: Path, dwell_seconds: int = 8) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = output.with_name(output.name + ".capture_tmp")
    if staging.exists():
        import shutil
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    if not app.is_dir():
        raise SystemExit(f"Simulator app missing: {app}")
    ocr = build_ocr()
    run("xcrun", "simctl", "ui", device, "appearance", "light")
    run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--cellularMode", "active", "--cellularBars", "4",
        "--batteryState", "charged", "--batteryLevel", "100")
    run("xcrun", "simctl", "terminate", device, BUNDLE_ID, check=False)
    run("xcrun", "simctl", "install", device, str(app))
    run("xcrun", "simctl", "launch", device, BUNDLE_ID)
    for index, page in enumerate(PAGES, 1):
        path = staging / filename(index, page)
        # A cold simulator launch can spend several seconds showing a blank
        # WebView before the first local HTML page is ready. Keep later page
        # transitions bounded while allowing that initial startup to finish.
        deadline = time.monotonic() + (90 if index == 1 else 30)
        while True:
            run("xcrun", "simctl", "io", device, "screenshot", str(path))
            try:
                validate_label(ocr, path, page)
                if "themillerhome" not in visible_text(ocr, path).replace(" ", ""):
                    raise SystemExit(f"{path.name}: shared header is not visible yet")
                break
            except SystemExit:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.5)
        time.sleep(1)
        run("xcrun", "simctl", "io", device, "screenshot", str(path))
        validate_label(ocr, path, page)
        print(f"captured {index:02d}/14 {page}", flush=True)
    manifest = {
        "revision": "design_shell_iphone16pro_ios18_6_light_v1",
        "source": "iPhone 16 Pro simulator, iOS 18.6, static local pilot design tour",
        "build_mode": "simulator_debug_only",
        "capture": {
            "advance_after_page_load_seconds": dwell_seconds,
            "label_validation": "macOS Vision OCR",
            "status_time": "9:41",
        },
        "app_executable_sha256": digest(app / "Runner"),
        "pages": {
            page: {
                "screenshot": filename(index, page),
                "png_sha256": digest(staging / filename(index, page)),
                "app_html_sha256": digest(ROOT / "assets/design_pages" / page / "app.html"),
            }
            for index, page in enumerate(PAGES, 1)
        },
    }
    (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if output.exists():
        import shutil
        shutil.rmtree(output)
    staging.rename(output)


def compare(baseline: Path, actual: Path, threshold: float) -> None:
    manifest = json.loads((baseline / "manifest.json").read_text())
    actual_manifest = json.loads((actual / "manifest.json").read_text())
    if tuple(manifest["pages"]) != PAGES:
        raise SystemExit("Baseline does not cover the expected 14 pages in order")
    if tuple(actual_manifest["pages"]) != PAGES:
        raise SystemExit("Actual capture does not cover the expected 14 pages in order")
    failed = []
    ocr = build_ocr()
    for page, record in manifest["pages"].items():
        if (digest(ROOT / "assets/design_pages" / page / "app.html") !=
                actual_manifest["pages"][page]["app_html_sha256"]):
            failed.append(f"{page}: packaged HTML changed since actual capture")
            continue
        before = baseline / record["screenshot"]
        after = actual / record["screenshot"]
        if digest(before) != record["png_sha256"]:
            failed.append(f"{page}: baseline PNG changed")
            continue
        if not after.is_file():
            failed.append(f"{page}: actual capture missing")
            continue
        if digest(after) != actual_manifest["pages"][page]["png_sha256"]:
            failed.append(f"{page}: actual PNG changed since capture")
            continue
        for image, label in ((before, "baseline"), (after, "actual")):
            try:
                validate_label(ocr, image, page)
            except SystemExit as error:
                failed.append(f"{page}: {label} label validation failed: {error}")
                break
        else:
            pass
        if failed and failed[-1].startswith(f"{page}:") and "label validation" in failed[-1]:
            continue
        result = subprocess.run((str(ocr), "--diff", str(before), str(after), ""),
                                capture_output=True, text=True)
        if result.returncode:
            failed.append(f"{page}: {result.stderr.strip() or 'image comparison failed'}")
            continue
        fraction = float(result.stdout.strip())
        if fraction > threshold:
            failed.append(f"{page}: {fraction:.3%} pixels changed")
        else:
            print(f"pass {page}: {fraction:.3%} pixels changed")
    if failed:
        raise SystemExit("Visual golden comparison failed:\n" + "\n".join(failed))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    capture_cmd = sub.add_parser("capture")
    capture_cmd.add_argument("--device", required=True, help="Booted simulator UDID")
    capture_cmd.add_argument("--out", type=Path, required=True)
    capture_cmd.add_argument("--app", type=Path, default=ROOT / "build/ios/iphonesimulator/Runner.app")
    capture_cmd.add_argument("--tour-dwell-seconds", type=int, default=8)
    compare_cmd = sub.add_parser("compare")
    compare_cmd.add_argument("--baseline", type=Path, required=True)
    compare_cmd.add_argument("--actual", type=Path, required=True)
    compare_cmd.add_argument("--max-changed-fraction", type=float, default=0.005)
    args = parser.parse_args()
    if args.command == "capture":
        capture(args.device, args.out, args.app, args.tour_dwell_seconds)
    else:
        if not 0 <= args.max_changed_fraction <= 1:
            parser.error("threshold must be between 0 and 1")
        compare(args.baseline, args.actual, args.max_changed_fraction)


if __name__ == "__main__":
    main()
