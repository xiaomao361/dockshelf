#!/usr/bin/env python3
"""Inspect a local archive without launching it, accessing accounts or uploading."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / ".build/app-store-validation/candidate"


def source_inputs():
    inputs = {}
    for folder in ["DockShelf", "DockShelf.xcodeproj", "scripts"]:
        for path in sorted((ROOT / folder).rglob("*")):
            if path.is_file() and ".DS_Store" != path.name and "xcuserdata" not in path.parts:
                inputs[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return inputs


def fingerprint(inputs):
    return hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def verify():
    inputs = source_inputs()
    before = json.loads((OUT / "source-before-build.json").read_text())
    assert inputs == before, "Source inputs changed while building; archive is not bound to current source"
    applications = OUT / "DockShelf.xcarchive/Products/Applications"
    apps = list(applications.glob("*.app"))
    assert len(apps) == 1, "Expected one application in archive"
    app = apps[0]
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.claracore.dockshelf"
    assert info["CFBundleShortVersionString"] == EXPECTED_VERSION
    assert info["CFBundleVersion"] == EXPECTED_BUILD
    assert info["LSMinimumSystemVersion"] == "14.0" and info["LSUIElement"] is True
    assert info["LSApplicationCategoryType"] == "public.app-category.utilities"
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    assert run("lipo", "-archs", str(binary)) == "arm64"
    run("codesign", "--verify", "--deep", "--strict", str(app))
    displayed = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)],
                               check=True, capture_output=True, text=True)
    entitlements = plistlib.loads(displayed.stdout.encode())
    expected = {"com.apple.security.app-sandbox": True,
                "com.apple.security.files.user-selected.read-only": True,
                "com.apple.security.files.bookmarks.app-scope": True}
    assert entitlements == expected, f"Unexpected Release entitlements: {entitlements}"
    manifest = plistlib.loads((app / "Contents/Resources/PrivacyInfo.xcprivacy").read_bytes())
    declared = {item["NSPrivacyAccessedAPIType"]: item["NSPrivacyAccessedAPITypeReasons"]
                for item in manifest["NSPrivacyAccessedAPITypes"]}
    assert declared == {"NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
                        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]}
    assert not manifest["NSPrivacyTracking"] and not manifest["NSPrivacyCollectedDataTypes"]
    assert "com.apple.quarantine" not in run("xattr", "-r", str(app)), "Quarantine in archive"
    symbols = run("nm", "-u", str(binary))
    suspicious = [line for line in symbols.splitlines()
                  if any(line.endswith(" " + symbol) for symbol in
                         ["_stat", "_fstat", "_lstat", "_statfs", "_fstatfs", "_getattrlist", "_getattrlistbulk"])]
    assert not suspicious, "New direct file metadata imports require privacy review"
    package = OUT / f"DockShelf-{EXPECTED_VERSION}-{EXPECTED_BUILD}-sandbox-local.zip"
    run("ditto", "-c", "-k", "--keepParent", str(app), str(package))
    signature = subprocess.run(["codesign", "-dvv", str(app)], check=True, capture_output=True, text=True).stderr
    receipt = {
        "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
        "baseCommit": run("git", "-C", str(ROOT), "rev-parse", "HEAD"),
        "branch": run("git", "-C", str(ROOT), "branch", "--show-current"),
        "sourceFingerprintSHA256": fingerprint(inputs), "sourceInputs": inputs,
        "entitlements": entitlements, "privacyReasons": declared, "architecture": "arm64",
        "localSignature": "ad hoc" if "Signature=adhoc" in signature else "inspect codesign output",
        "package": str(package.relative_to(ROOT)), "packageSHA256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "archive": str((OUT / "DockShelf.xcarchive").relative_to(ROOT)),
        "uiInteraction": "not run", "appStoreValidation": "not run", "upload": "not performed by this local verification",
    }
    (OUT / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in receipt.items() if k != "sourceInputs"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", action="store_true")
    parser.add_argument("--version", default="1.1")
    parser.add_argument("--build", default="2026103001")
    args = parser.parse_args()
    EXPECTED_VERSION, EXPECTED_BUILD = args.version, args.build
    OUT.mkdir(parents=True, exist_ok=True)
    if args.snapshot:
        (OUT / "source-before-build.json").write_text(json.dumps(source_inputs(), indent=2) + "\n")
    else:
        verify()
