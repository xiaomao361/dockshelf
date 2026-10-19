import SwiftUI

@MainActor
final class ShelfInteractionState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case receivingValid
        case receivingInvalid
        case returningShelfItem
        case success
        case partial(addedCount: Int, removedCount: Int, duplicateCount: Int, failedCount: Int)
        case invalid
        case replaced(count: Int)
        case duplicate
        case tooMany(limit: Int)
        case insufficientReplaceable(required: Int, available: Int)
        case restored
        case exporting
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastAddedCount = 0
    @Published var isPanelVisible = false
    @Published var isShowingDetails = false
    private var feedbackBeforeDrop: Phase?

    var hasPersistentFeedback: Bool { phase.isPersistentFeedback }

    var panelHoverChanged: ((Bool) -> Void)?
    var panelDropChanged: ((Bool) -> Void)?
    var dropFinished: ((ShelfStore.AddResult) -> Void)?
    var replacementUndone: (() -> Void)?
    var feedbackDismissed: (() -> Void)?
    var exportBegan: (() -> Void)?

    func showDropTarget(isValid: Bool) {
        isShowingDetails = false
        if !phase.isDropTarget {
            feedbackBeforeDrop = phase.isPersistentFeedback ? phase : nil
        }
        phase = isValid ? .receivingValid : .receivingInvalid
    }

    func panelDropEntered(isValid: Bool) {
        showDropTarget(isValid: isValid)
        panelDropChanged?(true)
    }

    func panelDropExited() {
        cancelDropTarget()
        panelDropChanged?(false)
    }

    func cancelDropTarget() {
        guard phase.isDropTarget else { return }
        phase = feedbackBeforeDrop ?? .idle
        feedbackBeforeDrop = nil
    }

    func finishDrop(result: ShelfStore.AddResult) {
        isShowingDetails = false
        feedbackBeforeDrop = nil
        switch result {
        case let .added(count):
            lastAddedCount = count
            phase = .success
        case let .replaced(addedCount, removedCount):
            lastAddedCount = addedCount
            phase = .replaced(count: removedCount)
        case let .partial(added, removed, duplicates, failed):
            lastAddedCount = added
            phase = .partial(addedCount: added, removedCount: removed, duplicateCount: duplicates, failedCount: failed)
        case .duplicate:
            lastAddedCount = 0
            phase = .duplicate
        case .invalid:
            lastAddedCount = 0
            phase = .invalid
        case let .tooMany(limit):
            lastAddedCount = 0
            phase = .tooMany(limit: limit)
        case let .insufficientReplaceable(required, available):
            lastAddedCount = 0
            phase = .insufficientReplaceable(required: required, available: available)
        }
        dropFinished?(result)
    }

    func showReplacementRestored() {
        isShowingDetails = false
        feedbackBeforeDrop = nil
        lastAddedCount = 0
        phase = .restored
        replacementUndone?()
    }

    func dismissFeedback() {
        isShowingDetails = false
        feedbackBeforeDrop = nil
        lastAddedCount = 0
        phase = .idle
        feedbackDismissed?()
    }

    func showReturningShelfItem() {
        phase = .returningShelfItem
    }

    func resumeExport() {
        phase = .exporting
    }

    func beginExport() {
        isShowingDetails = false
        phase = .exporting
        exportBegan?()
    }

    func reset() {
        feedbackBeforeDrop = nil
        lastAddedCount = 0
        isShowingDetails = false
        phase = .idle
    }
}

private extension ShelfInteractionState.Phase {
    var isPersistentFeedback: Bool {
        switch self {
        case .partial, .invalid, .replaced, .duplicate, .tooMany, .insufficientReplaceable:
            true
        case .idle, .receivingValid, .receivingInvalid, .returningShelfItem, .exporting, .success, .restored:
            false
        }
    }

    var isDropTarget: Bool {
        self == .receivingValid || self == .receivingInvalid
    }
}

/// Hover changes may cancel transient work but must never cancel completion feedback.
@MainActor
final class ShelfPanelTimers {
    private var transient: DispatchWorkItem?
    private var completion: DispatchWorkItem?
    private var transientGeneration = 0
    private var completionGeneration = 0

    func scheduleTransient(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancelTransient()
        let generation = transientGeneration
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transientGeneration == generation else { return }
                action()
            }
        }
        transient = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func scheduleCompletion(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancelCompletion()
        let generation = completionGeneration
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.completionGeneration == generation else { return }
                action()
            }
        }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelTransient() {
        transientGeneration += 1
        transient?.cancel()
        transient = nil
    }

    func cancelCompletion() {
        completionGeneration += 1
        completion?.cancel()
        completion = nil
    }

    deinit {
        transient?.cancel()
        completion?.cancel()
    }
}
