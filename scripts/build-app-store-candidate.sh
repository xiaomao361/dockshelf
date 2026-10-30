#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=.build/app-store-validation/candidate
mkdir -p "$output"
python3 scripts/verify-candidate.py --snapshot
for configuration in Debug Release AppStoreDebug; do
  xcodebuild -project DockShelf.xcodeproj -scheme DockShelf \
    -configuration "$configuration" -derivedDataPath .build/PolishValidation \
    build > "$output/$configuration.log" 2>&1
  rg 'warning:|BUILD (SUCCEEDED|FAILED)' "$output/$configuration.log" || true
done
xcodebuild -project DockShelf.xcodeproj -scheme DockShelf-AppStore \
  -configuration AppStoreRelease -derivedDataPath .build/AppStoreCandidate \
  -archivePath "$output/DockShelf.xcarchive" archive > "$output/archive.log" 2>&1
rg 'warning:|ARCHIVE (SUCCEEDED|FAILED)' "$output/archive.log" || true
python3 scripts/verify-candidate.py
