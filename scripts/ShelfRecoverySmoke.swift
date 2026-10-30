import Foundation

@main
struct ShelfRecoverySmoke {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try (0..<24).map { index -> URL in
            let url = root.appendingPathComponent("中文 same \(index).txt")
            try Data("original-\(index)".utf8).write(to: url)
            return url
        }
        let bytes = try files.map { try Data(contentsOf: $0) }
        let suite = "ShelfRecoverySmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let grants = Grants()
        let persistence = ShelfPersistence(defaults: defaults, recoveryDirectory: root.appendingPathComponent("Recovery"))
        let operations = grants.operations
        let missing = root.appendingPathComponent("not-here.txt")
        let date = Date(timeIntervalSince1970: 100)
        let legacy = [ShelfPinnedRecord(path: files[0].path, addedAt: date, bookmark: nil),
                      ShelfPinnedRecord(path: missing.path, addedAt: date, bookmark: nil),
                      ShelfPinnedRecord(path: root.path, addedAt: date.addingTimeInterval(1), bookmark: nil)]
        let legacyBytes = try JSONEncoder().encode(legacy)
        defaults.set(legacyBytes, forKey: ShelfPersistence.legacyKey)
        let store = ShelfStore(defaults: defaults, accessOperations: operations, persistence: persistence)
        check(store.items.map(\.id) == legacy.map(\.path), "legacy order including ties, missing file and folder survives")
        check(store.items.map(\.addedAt) == legacy.map(\.addedAt) && store.items.allSatisfy(\.isPinned), "migration preserves timestamps and pins")
        check(store.items.allSatisfy { $0.access?.state == .needsAuthorization }, "legacy path grants no authority")
        check(defaults.data(forKey: ShelfPersistence.legacyKey) == legacyBytes, "legacy original is untouched")
        check(defaults.data(forKey: ShelfPersistence.legacyBackupKey) == legacyBytes, "migration backup is byte exact")
        check(grants.starts == 0 && grants.bookmarks == 0, "migration never fabricates scope from paths")
        check(try persistence.load().records == legacy, "migrated archive round-trips semantically")
        check(ShelfStore(defaults: defaults, accessOperations: operations).items.count == 3, "second launch does not repeat or duplicate migration")

        let ids = store.items.map(\.id)
        check(store.add([files[0]]) == .reauthorized(count: 1), "same-path drop regrants existing pin")
        check(store.items.map(\.id) == ids && store.items[0].addedAt == date && store.items[0].isPinned, "regrant preserves identity, date, order and pin")
        check(store.items[0].access?.bookmark != nil, "regrant persists a bookmark")
        check(store.add([files[0]]) == .duplicate, "ordinary duplicate semantics unchanged")

        grants.stale = true
        var restored: ShelfStore? = ShelfStore(defaults: defaults, accessOperations: operations, persistence: persistence)
        check(restored?.items[0].access?.state == .ready, "saved grant resolves after relaunch")
        check(grants.bookmarks >= 2, "stale grant is refreshed")
        restored?.releaseAllAccess(); restored = nil
        grants.stale = false
        grants.relocated = files[1]
        let moved = ShelfStore(defaults: defaults, accessOperations: operations)
        check(moved.items[0].id == files[0].path && moved.items[0].access?.state == .locationChanged, "bookmark follow-move cannot change path identity")
        moved.releaseAllAccess()
        grants.relocated = nil
        grants.resolveFails = true
        let denied = ShelfStore(defaults: defaults, accessOperations: operations)
        check(denied.items.count == 3 && denied.items[0].access?.state == .needsAuthorization, "invalid bookmark remains a visible pin")
        denied.releaseAllAccess()
        grants.resolveFails = false
        grants.startAllowed = false
        let notStarted = ShelfStore(defaults: defaults, accessOperations: operations)
        check(notStarted.items[0].access?.state == .needsAuthorization, "failed start is distinct from ready")
        notStarted.releaseAllAccess()
        grants.startAllowed = true

        let validBytes = defaults.data(forKey: ShelfPersistence.currentKey)!
        let corrupt = Data("broken archive".utf8)
        defaults.set(corrupt, forKey: ShelfPersistence.currentKey)
        let broken = ShelfStore(defaults: defaults, accessOperations: operations, persistence: persistence)
        check(broken.persistenceProblem == .unreadable && broken.items.isEmpty && !broken.canModifyPinnedReferences, "bad archive is a visible failure, not a normal empty shelf")
        check(!broken.canExportPinnedReferences, "unreadable pins disable export")
        do { _ = try broken.exportPinnedReferences(); fatalError("corrupt shelf exported as empty") }
        catch { check(error as? ShelfPersistenceProblem == .unreadable, "corrupt export remains a detectable load failure") }
        _ = broken.add([files[2]])
        broken.togglePinned(broken.items[0])
        broken.clearAll()
        check(defaults.data(forKey: ShelfPersistence.currentKey) == corrupt, "bad bytes survive ordinary operations")
        check(broken.canRestoreBackup, "valid recovery copy is available")
        broken.restorePinnedBackup()
        check(broken.persistenceProblem == nil && broken.items.count == 3, "explicit recovery reloads pins")
        let rejected = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("DockShelf.pinnedItems.rejected.") }
        check(rejected.values.contains { ($0 as? Data) == corrupt }, "replaced bad bytes remain in preferences")
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        check(recoveryFiles.count == 1, "independent recovery copy written before replacement")
        let recoveryPlist = try PropertyListSerialization.propertyList(from: Data(contentsOf: recoveryFiles[0]), format: nil) as! [String: Any]
        check(recoveryPlist[ShelfPersistence.currentKey] as? Data == corrupt, "independent backup reopens and contains exact rejected data")
        broken.releaseAllAccess()
        defaults.set(validBytes, forKey: ShelfPersistence.currentKey)

        for malformed in [Data("[]".utf8), try JSONEncoder().encode(ShelfPinnedArchive(version: 9, items: [])),
                          try JSONEncoder().encode(ShelfPinnedArchive(version: 2, items: [legacy[0], legacy[0]]))] {
            defaults.set(malformed, forKey: ShelfPersistence.currentKey)
            let invalid = ShelfStore(defaults: defaults, accessOperations: operations)
            check(invalid.persistenceProblem == .unreadable, "invalid schema/version/duplicate never silently drops pins")
            check(defaults.data(forKey: ShelfPersistence.currentKey) == malformed, "invalid payload preserved")
        }
        defaults.set("wrong type", forKey: ShelfPersistence.currentKey)
        check(ShelfStore(defaults: defaults).persistenceProblem == .unreadable, "wrong defaults type is not no-data")
        defaults.set(validBytes, forKey: ShelfPersistence.currentKey)

        var shouldFailWrite = true
        let failing = ShelfPersistence(defaults: defaults, recoveryDirectory: root.appendingPathComponent("Recovery"), write: { data, key in
            if shouldFailWrite { throw ShelfPersistenceProblem.saveFailed }
            defaults.set(data, forKey: key)
        })
        let unsaved = ShelfStore(defaults: defaults, accessOperations: operations, persistence: failing)
        _ = unsaved.add([files[3]])
        unsaved.togglePinned(unsaved.items.last!)
        check(unsaved.persistenceProblem == .saveFailed, "write failure stays visible downstream")
        check(defaults.data(forKey: ShelfPersistence.currentKey) == validBytes, "write failure does not claim persisted changes")
        let rescue = try unsaved.exportPinnedReferences()
        check(rescue.includesUnsavedChanges && rescue.count == 4, "unsaved pin edits can be exported with an explicit warning")
        check(try persistence.decodeImport(rescue.data).count == 4, "rescue export includes actual intended pins")
        shouldFailWrite = false
        unsaved.retryPersistence()
        let savedCount = try persistence.load().records.count
        check(unsaved.persistenceProblem == nil && savedCount == 4, "retry persists intended unsaved state")
        unsaved.releaseAllAccess()

        store.clearAll()
        _ = store.add([files[0]])
        do {
            _ = try store.importPinnedReferences(legacyBytes)
            fatalError("conflicting imported pin accepted as temporary")
        } catch {
            check(error as? ShelfPersistenceProblem == .importConflict && !store.items[0].isPinned,
                  "conflicting imported pin stays explicitly unresolved without changing current reference")
        }

        // Export/import is one portable workflow: no temporary items, grants or
        // private file content in the archive; missing locations remain records.
        store.clearAll()
        check(!store.canExportPinnedReferences, "empty shelf disables export")
        do { _ = try store.exportPinnedReferences(); fatalError("empty shelf exported") }
        catch { check(error is ShelfReferenceExportProblem, "empty export has an explicit failure") }
        _ = try store.importPinnedReferences(legacyBytes)
        _ = store.add([files[0]]) // Existing grant must survive a backup round trip.
        _ = store.add([files[5]]) // Temporary file must be excluded.
        let persistedBeforeExport = defaults.data(forKey: ShelfPersistence.currentKey)
        // Snapshot values only: retaining ShelfItems would itself retain their
        // grants and invalidate the final access-lifecycle assertion.
        let pathsBeforeExport = store.items.map(\.id)
        let datesBeforeExport = store.items.map(\.addedAt)
        let pinsBeforeExport = store.items.map(\.isPinned)
        let document = try store.exportPinnedReferences()
        let expectedExport = legacy.map { ShelfPinnedRecord(path: $0.path, addedAt: $0.addedAt, bookmark: $0.path == files[0].path ? Data(files[0].path.utf8) : nil) }
        check(document.count == 3 && document.bookmarkCount == 1 && !document.includesUnsavedChanges, "export counts only pinned references")
        check(try persistence.decodeImport(document.data) == expectedExport, "export preserves folder/missing path, order and time")
        let object = try JSONSerialization.jsonObject(with: document.data) as! [String: Any]
        let exportedRows = object["items"] as! [[String: Any]]
        check(object["version"] as? Int == 3 && exportedRows[0]["bookmark"] != nil, "v3 backup preserves existing access bookmark")
        check(exportedRows.allSatisfy { Set($0.keys).isSubset(of: ["path", "addedAt", "bookmark"]) }, "backup includes references and bookmarks, never original file content")
        let exportDirectory = root.appendingPathComponent("Exports")
        let exportedFile = try document.write(to: exportDirectory)
        let secondExport = try document.write(to: exportDirectory)
        check(exportedFile != secondExport, "repeated export never replaces the previous backup")
        check(try Data(contentsOf: exportedFile) == document.data, "export file bytes match prepared archive")
        let attributes = try FileManager.default.attributesOfItem(atPath: exportedFile.path)
        check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "backup containing access information is owner-readable/writable only")
        do {
            _ = try persistence.encodeExport([ShelfPinnedRecord(path: files[0].path, addedAt: date, bookmark: Data(repeating: 1, count: 1_600_000))])
            fatalError("unimportable oversized backup exported")
        } catch { check(error as? ShelfReferenceExportProblem == .tooLarge, "export size bound matches supported import size") }
        let importSuite = suite + ".roundtrip"
        let importDefaults = UserDefaults(suiteName: importSuite)!
        defer { importDefaults.removePersistentDomain(forName: importSuite) }
        let receiver = ShelfStore(defaults: importDefaults, accessOperations: operations)
        check(try receiver.importPinnedReferences(Data(contentsOf: exportedFile)) == 3, "generated file imports into a fresh shelf")
        check(receiver.items.map(\.id) == legacy.map(\.path) && receiver.items.map(\.addedAt) == legacy.map(\.addedAt), "real export file round-trip preserves all reference semantics")
        check(receiver.items.allSatisfy(\.isPinned) && receiver.items[0].access?.state == .ready && receiver.lastImportedRestoredCount == 1,
              "backup automatically restores existing access while retaining all fixed references")
        check(receiver.items[1].access?.state == .needsAuthorization && receiver.items[2].access?.state == .needsAuthorization,
              "records lacking bookmarks remain explicitly pending")
        check(try receiver.importPinnedReferences(Data(contentsOf: exportedFile)) == 0, "round-trip reimport is idempotent")
        receiver.clearAll()
        _ = try receiver.importPinnedReferences(legacyBytes)
        check(receiver.items.allSatisfy { $0.access?.state == .needsAuthorization }, "old path-only backups remain supported without invented grants")
        let recoveryIDs = Set(receiver.items.map(\.id))
        let wrongDirectory = root.appendingPathComponent("different-folder")
        try FileManager.default.createDirectory(at: wrongDirectory, withIntermediateDirectories: true)
        let sameNameElsewhere = wrongDirectory.appendingPathComponent(files[0].lastPathComponent)
        try Data("other file".utf8).write(to: sameNameElsewhere)
        let bookmarksBeforeMismatch = grants.bookmarks
        check(receiver.add([sameNameElsewhere], reauthorizing: recoveryIDs) == .invalid, "recovery cannot substitute a same-name file at a different path")
        check(receiver.lastImportIssues.first?.reason == .notRequestedReference && receiver.items.count == 3,
              "mismatched selection has a specific visible reason and cannot add a reference")
        check(grants.bookmarks == bookmarksBeforeMismatch, "wrong-path selection never creates a durable grant")
        grants.bookmarkFails = true
        check(receiver.add([files[0]], reauthorizing: recoveryIDs) == .invalid, "failed durable grant is not reported as reauthorized")
        check(receiver.items[0].access?.state == .needsAuthorization && receiver.lastImportIssues.first?.reason == .authorization,
              "failed grant preserves previous pending reference")
        grants.bookmarkFails = false
        let deniedSelection = ShelfPreparedReference(access: nil, availability: .accessDenied)
        check(receiver.add([files[0]], prepared: [deniedSelection], reauthorizing: recoveryIDs) == .invalid,
              "denied original selection remains failure")
        check(receiver.lastImportIssues.first?.reason == .accessDenied, "access denied is not mislabeled as missing")
        check(receiver.add([files[0], sameNameElsewhere], reauthorizing: recoveryIDs)
              == .partial(addedCount: 0, removedCount: 0, duplicateCount: 0, failedCount: 1), "mixed selection preserves partial recovery and mismatch failure")
        check(receiver.lastReauthorizedCount == 1 && receiver.items[0].access?.state == .ready && receiver.items.count == 3,
              "partial recovery never changes capacity or invents an addition")
        check(receiver.add([root], reauthorizing: recoveryIDs) == .reauthorized(count: 1), "folder can be authorized through the same strict selection path")
        check(receiver.items.map(\.id) == legacy.map(\.path) && receiver.items.map(\.addedAt) == legacy.map(\.addedAt)
              && receiver.items.allSatisfy(\.isPinned), "selection recovery retains paths/order/dates/pins including missing original")
        check(receiver.items[1].access?.state == .needsAuthorization, "unselected or missing original remains pending, not deleted")
        let afterRecovery = ShelfStore(defaults: importDefaults, accessOperations: operations)
        check(afterRecovery.items[0].access?.state == .ready && afterRecovery.items[2].access?.state == .ready,
              "new model reloads saved original-file and folder grants")
        afterRecovery.releaseAllAccess()
        let queuedTarget = receiver.items[1]
        await withCheckedContinuation { continuation in
            receiver.enqueueImport([missing], failedCount: 0, issues: [], reauthorizing: [queuedTarget.id]) { result in
                check(result == .invalid && receiver.lastImportIssues.first?.reason == .notRequestedReference,
                      "queued recovery rechecks that target still exists")
                check(!receiver.items.contains { $0.id == queuedTarget.id }, "removal during pending recovery cannot resurrect a reference")
                continuation.resume()
            }
            receiver.remove(queuedTarget)
        }
        receiver.releaseAllAccess()
        do { _ = try document.write(to: files[0]); fatalError("export into file unexpectedly succeeded") }
        catch {} // Concrete I/O failure, never a success path.
        check(store.items.map(\.id) == pathsBeforeExport && store.items.map(\.addedAt) == datesBeforeExport
              && store.items.map(\.isPinned) == pinsBeforeExport
              && defaults.data(forKey: ShelfPersistence.currentKey) == persistedBeforeExport,
              "successful and failed exports do not change current items or saved records")
        check(try Data(contentsOf: files[0]) == bytes[0], "failed export cannot overwrite an original file")

        // Portable import: merge, capacity rejection, corruption and failure atomicity.
        store.clearAll()
        let imported = try JSONEncoder().encode(Array(legacy.prefix(2)))
        check(try store.importPinnedReferences(imported) == 2, "portable import keeps missing references")
        check(store.items.map(\.id) == Array(legacy.prefix(2)).map(\.path), "import preserves order")
        check(try store.importPinnedReferences(imported) == 0, "reimport is idempotent")
        check(store.items.allSatisfy { $0.access?.state == .needsAuthorization }, "path-only legacy import cannot fabricate grants")
        let beforeImport = store.items
        let oversized = try JSONEncoder().encode(files.map { ShelfPinnedRecord(path: $0.path, addedAt: date, bookmark: nil) })
        do { _ = try store.importPinnedReferences(oversized); fatalError("oversize import accepted") } catch {}
        check(store.items == beforeImport, "oversized import leaves current shelf intact")
        do { _ = try store.importPinnedReferences(corrupt); fatalError("corrupt import accepted") } catch {}
        check(store.items == beforeImport, "bad import leaves current shelf intact")
        let plist = try PropertyListSerialization.data(fromPropertyList: [ShelfPersistence.legacyKey: legacyBytes], format: .xml, options: 0)
        check(try persistence.decodeImport(plist) == legacy, "exported legacy preference plist is supported")

        _ = store.add(Array(files[1..<19]))
        for item in store.items where !item.isPinned { store.togglePinned(item) }
        check(store.add([files[0], files[20]]) == .insufficientReplaceable(required: 1, available: 0), "capacity refusal includes regrant in rejected batch")
        check(store.items[0].access?.state == .needsAuthorization, "rejected batch changes no existing access state")
        store.togglePinned(store.items[2])
        _ = store.add([files[20]])
        check(store.canUndoReplacement, "replacement snapshot exists before regrant")
        _ = store.add([files[0]])
        check(store.canUndoReplacement && store.undoLastReplacement(), "regrant preserves existing undo")
        check(store.items[0].access?.state == .ready, "undo retains newly granted access for same fixed identity")

        store.clearAll()
        _ = store.add([files[4]])
        grants.bookmarkFails = true
        store.togglePinned(store.items[0])
        check(!store.items[0].isPinned && store.accessWarning != nil, "failed bookmark never masquerades as a durable pin")
        check(store.items[0].access?.canReadCurrentSession == true, "failed durable bookmark does not revoke current temporary access")
        grants.bookmarkFails = false
        store.togglePinned(store.items[0])
        check(store.items[0].isPinned, "bookmark retry can pin")
        store.clearAll()

        let failedRecoverySuite = suite + ".failed-recovery"
        let failedRecoveryDefaults = UserDefaults(suiteName: failedRecoverySuite)!
        defer { failedRecoveryDefaults.removePersistentDomain(forName: failedRecoverySuite) }
        var failRecoverySave = false
        let recoveryPersistence = ShelfPersistence(defaults: failedRecoveryDefaults, write: { data, key in
            if failRecoverySave { throw ShelfPersistenceProblem.saveFailed }
            failedRecoveryDefaults.set(data, forKey: key)
        })
        let unsavedRecovery = ShelfStore(defaults: failedRecoveryDefaults, accessOperations: operations, persistence: recoveryPersistence)
        _ = try unsavedRecovery.importPinnedReferences(legacyBytes)
        let recoveryBytesBeforeFailure = failedRecoveryDefaults.data(forKey: ShelfPersistence.currentKey)
        failRecoverySave = true
        check(unsavedRecovery.add([files[0]], reauthorizing: [files[0].path]) == .reauthorized(count: 1), "current-session access can recover while storage fails")
        check(unsavedRecovery.items[0].access?.state == .ready && unsavedRecovery.persistenceProblem == .saveFailed,
              "authorization cannot hide unsaved fixed changes")
        check(failedRecoveryDefaults.data(forKey: ShelfPersistence.currentKey) == recoveryBytesBeforeFailure,
              "failed recovery save never claims a persistent grant")
        failRecoverySave = false
        unsavedRecovery.retryPersistence()
        check(unsavedRecovery.persistenceProblem == nil, "recovery grant save can be retried")
        unsavedRecovery.clearAll()
        _ = try unsavedRecovery.importPinnedReferences(legacyBytes)
        let pendingBackupBytes = failedRecoveryDefaults.data(forKey: ShelfPersistence.currentKey)
        failRecoverySave = true
        do { _ = try unsavedRecovery.importPinnedReferences(document.data); fatalError("failed backup commit accepted") }
        catch { check(error as? ShelfPersistenceProblem == .saveFailed, "automatic restore failure remains a save error") }
        check(unsavedRecovery.items[0].access?.state == .needsAuthorization && unsavedRecovery.lastImportedRestoredCount == 0
              && failedRecoveryDefaults.data(forKey: ShelfPersistence.currentKey) == pendingBackupBytes,
              "failed import cannot publish new access or overwrite existing metadata")
        failRecoverySave = false
        let differentDates = expectedExport.map { ShelfPinnedRecord(path: $0.path, addedAt: $0.addedAt.addingTimeInterval(500), bookmark: $0.bookmark) }
        check(try unsavedRecovery.importPinnedReferences(persistence.encodeExport(differentDates)) == 0,
              "backup can repair existing pending records without duplicate additions")
        check(unsavedRecovery.lastImportedRestoredCount == 1 && unsavedRecovery.items[0].access?.state == .ready
              && unsavedRecovery.items.map(\.addedAt) == legacy.map(\.addedAt), "automatic permission repair retains current metadata")
        grants.resolveFails = true
        check(try unsavedRecovery.importPinnedReferences(document.data) == 0 && unsavedRecovery.items[0].access?.state == .ready,
              "unusable backup never replaces existing working access")
        grants.resolveFails = false
        unsavedRecovery.releaseAllAccess()

        // Folder-level recovery: one selection restores multiple known paths.
        let bulkRoot = root.appendingPathComponent("bulk")
        let nested = bulkRoot.appendingPathComponent("nested")
        let sibling = root.appendingPathComponent("bulk-sibling")
        for directory in [nested, sibling] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let bulkLog = nested.appendingPathComponent("build.log")
        try Data("bulk log".utf8).write(to: bulkLog)
        let app = bulkRoot.appendingPathComponent("sample.app")
        let archive = bulkRoot.appendingPathComponent("sample.xcarchive")
        for directory in [app, archive] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let siblingFile = sibling.appendingPathComponent("build.log")
        try Data("outside".utf8).write(to: siblingFile)
        let link = bulkRoot.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: siblingFile)
        let bulkMissing = bulkRoot.appendingPathComponent("missing.log")
        let bulkURLs = [bulkLog, app, archive, siblingFile, link, bulkMissing]
        let bulkRecords = bulkURLs.map { ShelfPinnedRecord(path: $0.path, addedAt: date, bookmark: nil) }
        let bulkSuite = suite + ".folder"
        let bulkDefaults = UserDefaults(suiteName: bulkSuite)!
        defer { bulkDefaults.removePersistentDomain(forName: bulkSuite) }
        let bulk = ShelfStore(defaults: bulkDefaults, accessOperations: operations)
        _ = try bulk.importPinnedReferences(JSONEncoder().encode(bulkRecords))
        let bulkIDs = Set(bulkURLs.map(\.path))
        await withCheckedContinuation { continuation in
            bulk.enqueueFolderReauthorization([bulkRoot], targetIDs: bulkIDs) { result in
                check(result == .partial(addedCount: 0, removedCount: 0, duplicateCount: 0, failedCount: 2),
                      "folder recovery separates missing and escaped-link failures from restored references")
                check(bulk.lastReauthorizedCount == 3, "one folder restores log, app and archive together without selecting each file")
                continuation.resume()
            }
        }
        check(bulk.items.prefix(3).allSatisfy { $0.access?.state == .ready } && bulk.items.suffix(3).allSatisfy { $0.access?.state == .needsAuthorization },
              "prefix sibling, symlink escape and missing file cannot become false successful restorations")
        check(bulk.items.map(\.id) == bulkRecords.map(\.path) && bulk.items.map(\.addedAt) == bulkRecords.map(\.addedAt)
              && bulk.items.allSatisfy(\.isPinned), "folder recovery never changes reference membership/order/time/pins")
        check(bulk.lastImportIssues.contains { $0.reason == .outsideSelectedFolder } && bulk.lastImportIssues.contains { $0.reason == .unavailable }, "folder issues retain distinct failure states")
        let folderBackup = try bulk.exportPinnedReferences()
        check(folderBackup.bookmarkCount == 3, "folder-granted child access is included in the next backup")
        let autoSuite = suite + ".automatic-backup"
        let autoDefaults = UserDefaults(suiteName: autoSuite)!
        defer { autoDefaults.removePersistentDomain(forName: autoSuite) }
        let automatic = ShelfStore(defaults: autoDefaults, accessOperations: operations)
        check(try automatic.importPinnedReferences(folderBackup.data) == 6 && automatic.lastImportedRestoredCount == 3,
              "one backup import automatically restores multiple grants without any file selections")
        check(automatic.items.prefix(3).allSatisfy { $0.access?.state == .ready }, "all available backed-up grants become usable together")
        automatic.releaseAllAccess()
        bulk.releaseAllAccess()
        let bulkReopened = ShelfStore(defaults: bulkDefaults, accessOperations: operations)
        check(bulkReopened.items.prefix(3).allSatisfy { $0.access?.state == .ready }, "folder-recovered child bookmarks reload in a new model")
        await withCheckedContinuation { continuation in
            bulkReopened.enqueueFolderReauthorization([wrongDirectory], targetIDs: bulkIDs) { result in
                check(result == .invalid && bulkReopened.lastImportIssues.first?.reason == .folderDoesNotContainReferences,
                      "unrelated folder returns an actionable failure rather than guessing filenames")
                continuation.resume()
            }
        }
        bulkReopened.releaseAllAccess()
        grants.resolveFails = true
        let foreign = ShelfStore(defaults: bulkDefaults, accessOperations: operations)
        check(foreign.items.allSatisfy { $0.access?.state == .needsAuthorization }, "unresolvable grants retain all records as pending")
        foreign.releaseAllAccess()
        grants.resolveFails = false
        check(try Data(contentsOf: bulkLog) == Data("bulk log".utf8) && Data(contentsOf: siblingFile) == Data("outside".utf8),
              "folder recovery does not modify original content")

        // Serial native import commits preserve input ordering while probes await.
        await withCheckedContinuation { continuation in
            var completions = 0
            let startsBeforeQueue = grants.starts
            for index in 0..<2 {
                store.enqueueImport([files[index]], failedCount: 0, issues: []) { result in
                    check(result == .added(count: 1), "queued result reports actual committed count")
                    completions += 1
                    if completions == 2 { continuation.resume() }
                }
            }
            check(grants.starts == startsBeforeQueue + 2, "native boundary retains grants before deferred probes start")
        }
        check(store.items.map(\.id) == [files[0].path, files[1].path] && store.pendingImportCount == 0, "queued import order and pending lifecycle")
        store.clearAll()

        let cycleStart = Date()
        for _ in 0..<100 {
            _ = store.add(Array(files.prefix(20)))
            let original = store.items.map(\.id)
            _ = store.add([files[20]])
            check(store.canUndoReplacement, "replacement holds access for undo")
            check(store.undoLastReplacement() && store.items.map(\.id) == original, "undo restores exact identities")
            store.clearTemporaryItems()
        }
        store.releaseAllAccess()
        check(grants.active == 0 && grants.starts == grants.stops, "all successful scopes balance after undo/remove/clear/termination and rejected batches")
        check(try files.map { try Data(contentsOf: $0) } == bytes, "all source bytes remain unchanged")
        print("Shelf recovery smoke passed: migration/backup round-trip, no fake grants, stale/moved/denied bookmarks, corrupt/save failures, explicit restore, bookmark backup round-trip, folder bulk recovery, strict original-file selection recovery, partial/wrong-path/denied/save-failure outcomes, serial queues, 100 undo cycles, balanced scopes; cycles=\(String(format: "%.3f", Date().timeIntervalSince(cycleStart)))s")
    }

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        do {
            guard try condition() else { fatalError("Failed: \(message)") }
        } catch { fatalError("Failed: \(message): \(error)") }
    }

    final class Grants: @unchecked Sendable {
        private let lock = NSLock()
        private var startCount = 0
        private var stopCount = 0
        private var bookmarkCount = 0
        var startAllowed = true
        var bookmarkFails = false
        var resolveFails = false
        var stale = false
        var relocated: URL?
        var starts: Int { lock.withLock { startCount } }
        var stops: Int { lock.withLock { stopCount } }
        var bookmarks: Int { lock.withLock { bookmarkCount } }
        var active: Int { starts - stops }
        var operations: ShelfAccessOperations {
            ShelfAccessOperations(start: { [self] _ in
                guard startAllowed else { return false }
                lock.withLock { startCount += 1 }; return true
            }, stop: { [self] _ in lock.withLock { stopCount += 1 } }, bookmark: { [self] url in
                if bookmarkFails { throw ShelfPersistenceProblem.saveFailed }
                lock.withLock { bookmarkCount += 1 }
                return Data(url.path.utf8)
            }, resolve: { [self] data in
                if resolveFails { throw ShelfPersistenceProblem.unreadable }
                return (relocated ?? URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), stale)
            })
        }
    }
}
