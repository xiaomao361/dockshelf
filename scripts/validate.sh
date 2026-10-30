#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
validation_dir=$(mktemp -d "${TMPDIR:-/tmp}/dockshelf-validation.XXXXXX")
trap 'rm -rf "$validation_dir"' EXIT
model=(DockShelf/ShelfFileAccess.swift DockShelf/ShelfPersistence.swift DockShelf/ShelfStore.swift)
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library "${model[@]}" scripts/ShelfStoreSmoke.swift -o "$validation_dir/store"
"$validation_dir/store"
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library "${model[@]}" DockShelf/ShelfInteractionState.swift scripts/ShelfInteractionSmoke.swift -o "$validation_dir/interaction"
"$validation_dir/interaction"
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library "${model[@]}" DockShelf/ShelfInteractionState.swift DockShelf/ShelfImport.swift DockShelf/ShelfView.swift DockShelf/DockShelfTheme.swift DockShelf/ShelfShortcut.swift DockShelf/ShelfDragMonitor.swift scripts/ShelfRefinementSmoke.swift -o "$validation_dir/refinement"
"$validation_dir/refinement"
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library "${model[@]}" scripts/ShelfRecoverySmoke.swift -o "$validation_dir/recovery"
"$validation_dir/recovery"
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library DockShelf/ShelfShortcut.swift scripts/ShelfShortcutSmoke.swift -o "$validation_dir/shortcut"
"$validation_dir/shortcut"
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library "${model[@]}" DockShelf/ShelfInteractionState.swift DockShelf/ShelfImport.swift DockShelf/ShelfView.swift DockShelf/DockShelfTheme.swift scripts/ShelfDropTargetSmoke.swift -o "$validation_dir/drop-target"
"$validation_dir/drop-target"
