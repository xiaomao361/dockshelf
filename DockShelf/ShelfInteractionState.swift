import SwiftUI

@MainActor
final class ShelfInteractionState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case receivingValid
        case receivingInvalid
        case success
        case exporting
    }

    @Published private(set) var phase: Phase = .idle

    var panelHoverChanged: ((Bool) -> Void)?
    var panelDropChanged: ((Bool) -> Void)?
    var dropFinished: ((Bool) -> Void)?
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
        if phase != .success && phase != .exporting {
            phase = .idle
        }
    }

    func finishDrop(addedItems: Bool) {
        phase = addedItems ? .success : .receivingInvalid
        dropFinished?(addedItems)
    }

    func beginExport() {
        phase = .exporting
        exportBegan?()
    }

    func reset() {
        phase = .idle
    }
}
