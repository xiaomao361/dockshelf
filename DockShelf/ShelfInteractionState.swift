import SwiftUI

@MainActor
final class ShelfInteractionState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case receivingValid
        case receivingInvalid
        case returningShelfItem
        case success
        case invalid
        case replaced(count: Int)
        case duplicate
        case tooMany(limit: Int)
        case insufficientReplaceable(required: Int, available: Int)
        case restored
        case exporting
    }

    @Published private(set) var phase: Phase = .idle

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
        case .success, .invalid, .replaced, .duplicate, .tooMany, .insufficientReplaceable, .restored:
            true
        case .idle, .receivingValid, .receivingInvalid, .returningShelfItem, .exporting:
            false
        }
    }
}
