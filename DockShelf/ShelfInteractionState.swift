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
    @Published var isPanelVisible = false

    var panelHoverChanged: ((Bool) -> Void)?
    var panelDropChanged: ((Bool) -> Void)?
    var dropFinished: ((ShelfStore.AddResult) -> Void)?
    var replacementUndone: (() -> Void)?
    var feedbackDismissed: (() -> Void)?
    var exportBegan: (() -> Void)?

    func showDropTarget(isValid: Bool) {
        phase = isValid ? .receivingValid : .receivingInvalid
    }

    func panelDropEntered(isValid: Bool) {
        showDropTarget(isValid: isValid)
        panelDropChanged?(true)
    }

    func panelDropExited() {
        panelDropChanged?(false)
        if !phase.isFeedback && phase != .exporting {
            phase = .idle
        }
    }

    func finishDrop(result: ShelfStore.AddResult) {
        switch result {
        case .added:
            phase = .success
        case let .replaced(_, removedCount):
            phase = .replaced(count: removedCount)
        case let .partial(added, removed, duplicates, failed):
            phase = .partial(addedCount: added, removedCount: removed, duplicateCount: duplicates, failedCount: failed)
        case .duplicate:
            phase = .duplicate
        case .invalid:
            phase = .invalid
        case let .tooMany(limit):
            phase = .tooMany(limit: limit)
        case let .insufficientReplaceable(required, available):
            phase = .insufficientReplaceable(required: required, available: available)
        }
        dropFinished?(result)
    }

    func showReplacementRestored() {
        phase = .restored
        replacementUndone?()
    }

    func dismissFeedback() {
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
        phase = .exporting
        exportBegan?()
    }

    func reset() {
        phase = .idle
    }
}

private extension ShelfInteractionState.Phase {
    var isFeedback: Bool {
        switch self {
        case .success, .partial, .invalid, .replaced, .duplicate, .tooMany, .insufficientReplaceable, .restored:
            true
        case .idle, .receivingValid, .receivingInvalid, .returningShelfItem, .exporting:
            false
        }
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
