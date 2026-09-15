import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    private enum PresentationReason {
        case manual
        case automatic
        case hover
        case drop
        case export
    }

    private let store: ShelfStore
    private let interaction = ShelfInteractionState()
    private let panel: ShelfPanel
    private let panelSize = NSSize(
        width: DockShelfMetrics.panelSize.width,
        height: DockShelfMetrics.panelSize.height
    )

    private weak var anchorButton: NSStatusBarButton?
    private var presentationReason: PresentationReason = .manual
    private var isStatusHovered = false
    private var isPanelHovered = false
    private var isStatusDragActive = false
    private var isPanelDragActive = false
    private let timers = ShelfPanelTimers()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var animationGeneration = 0
    private var automaticSession: UUID?

    init(store: ShelfStore) {
        self.store = store
        panel = ShelfPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        interaction.panelHoverChanged = { [weak self] isHovering in
            self?.panelHoverChanged(isHovering)
        }
        interaction.panelDropChanged = { [weak self] isActive in
            self?.panelDropChanged(isActive)
        }
        interaction.dropFinished = { [weak self] result in
            self?.finishDrop(result: result)
        }
        interaction.replacementUndone = { [weak self] in
            self?.timers.scheduleCompletion(after: 0.5) { [weak self] in
                self?.close()
            }
        }
        interaction.feedbackDismissed = { [weak self] in
            self?.returnToShelf()
        }
        interaction.exportBegan = { [weak self] in
            self?.beginExport()
        }

        panel.delegate = self
        panel.cancelHandler = { [weak self] in self?.close() }
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = ShelfHostingView(store: store, interaction: interaction)
    }

    func toggleManual(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            if presentationReason == .hover {
                show(relativeTo: button, reason: .manual, activate: true)
            } else {
                close()
            }
            return
        }

        show(relativeTo: button, reason: .manual, activate: true)
    }

    func showManual(relativeTo button: NSStatusBarButton) {
        show(relativeTo: button, reason: .manual, activate: true)
    }

    func showUsingShortcut(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            close()
            return
        }
        let isDragging = NSEvent.pressedMouseButtons & 1 != 0
        show(relativeTo: button, reason: .manual, activate: !isDragging)
        if isDragging { installOutsideClickMonitors() }
    }

    func showForAutomaticDrag(relativeTo button: NSStatusBarButton) {
        guard !panel.isVisible else { return }
        automaticSession = UUID()
        show(relativeTo: button, reason: .automatic, activate: false)
    }

    func automaticDragEnded() {
        guard let session = automaticSession else { return }
        // Native performDragOperation may arrive after the mouse-up observation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.automaticSession == session else { return }
            self.close()
        }
    }

    func statusHoverChanged(_ isHovering: Bool, relativeTo button: NSStatusBarButton) {
        isStatusHovered = isHovering
        anchorButton = button

        guard !isStatusDragActive else { return }

        if isHovering {
            cancelPendingWork()
            guard !panel.isVisible, !store.items.isEmpty else { return }
            schedule(after: 0.3) { [weak self, weak button] in
                guard let self, let button, self.isStatusHovered else { return }
                self.show(relativeTo: button, reason: .hover, activate: false)
            }
        } else if panel.isVisible && presentationReason == .hover {
            scheduleTransientClose(after: 0.28)
        }
    }

    func statusDragEntered(relativeTo button: NSStatusBarButton, isValid: Bool) {
        isStatusDragActive = true
        cancelPendingWork()
        show(relativeTo: button, reason: .drop, activate: false)
        interaction.showDropTarget(isValid: isValid)
    }

    func statusDragUpdated(isValid: Bool) {
        interaction.showDropTarget(isValid: isValid)
    }

    func statusDragExited() {
        isStatusDragActive = false
        if !isPanelDragActive {
            scheduleTransientClose(after: 0.45)
        }
    }

    @discardableResult
    func receiveStatusDrop(_ batch: ShelfImport.Batch) -> Bool {
        isStatusDragActive = false
        let result = store.add(batch.urls, failedCount: batch.failedCount)
        interaction.finishDrop(result: result)
        return result.accepted
    }

    func close() {
        timers.cancelCompletion()
        automaticSession = nil
        cancelPendingWork()
        removeEventMonitors()
        isStatusDragActive = false
        isPanelDragActive = false
        interaction.isPanelVisible = false
        interaction.reset()
        animateOut()
    }

    private func show(
        relativeTo button: NSStatusBarButton,
        reason: PresentationReason,
        activate: Bool
    ) {
        timers.cancelCompletion()
        cancelPendingWork()
        removeEventMonitors()
        if anchorButton !== button, let previousButton = anchorButton {
            applyAnchorHighlight(false, to: previousButton)
        }
        anchorButton = button
        presentationReason = reason
        interaction.isPanelVisible = true
        animationGeneration += 1
        panel.animations.removeAll()

        let targetOrigin = origin(relativeTo: button)
        let wasVisible = panel.isVisible
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if wasVisible {
            panel.setFrameOrigin(targetOrigin)
            panel.alphaValue = 1
        } else {
            let startOrigin = NSPoint(
                x: targetOrigin.x,
                y: targetOrigin.y + (reduceMotion ? 0 : 6)
            )
            panel.setFrameOrigin(startOrigin)
            panel.alphaValue = 0
        }

        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitors()
        } else {
            panel.orderFrontRegardless()
        }
        setAnchorHighlighted(true)

        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.2,
                    0,
                    0,
                    1
                )
                panel.animator().alphaValue = 1
                if !reduceMotion {
                    panel.animator().setFrameOrigin(targetOrigin)
                }
            }
        }

#if DEBUG
        NSLog(
            "Shelf panel shown at %@, visible=%@, reason=%@",
            NSStringFromRect(panel.frame),
            panel.isVisible ? "true" : "false",
            String(describing: reason)
        )
#endif
    }

    private func panelHoverChanged(_ isHovering: Bool) {
        isPanelHovered = isHovering
        if isHovering {
            cancelPendingWork()
        } else if presentationReason == .hover && !isStatusHovered {
            scheduleTransientClose(after: 0.28)
        }
    }

    private func panelDropChanged(_ isActive: Bool) {
        isPanelDragActive = isActive
        if isActive {
            timers.cancelCompletion()
            cancelPendingWork()
            if automaticSession == nil { presentationReason = .drop }
        } else if automaticSession == nil && !isStatusDragActive {
            scheduleTransientClose(after: 0.45)
        }
    }

    private func finishDrop(result: ShelfStore.AddResult) {
        timers.cancelCompletion()
        automaticSession = nil
        isStatusDragActive = false
        isPanelDragActive = false
        presentationReason = .drop
        cancelPendingWork()

        let closeDelay: TimeInterval?
        switch result {
        case .added:
            closeDelay = 0.35
        case .replaced:
            closeDelay = nil
            installOutsideClickMonitors()
        case .partial, .duplicate, .invalid, .tooMany, .insufficientReplaceable:
            closeDelay = nil
            installOutsideClickMonitors()
        }

        if let closeDelay {
            timers.scheduleCompletion(after: closeDelay) { [weak self] in
                self?.close()
            }
        }
    }

    private func beginExport() {
        timers.cancelCompletion()
        automaticSession = nil
        cancelPendingWork()
        presentationReason = .export
        removeEventMonitors()
        installExportEndMonitors()

        schedule(after: 15) { [weak self] in
            self?.finishExport()
        }
    }

    private func returnToShelf() {
        timers.cancelCompletion()
        cancelPendingWork()
        removeEventMonitors()
        presentationReason = .manual
        installOutsideClickMonitors()
    }

    private func finishExport() {
        guard presentationReason == .export else { return }
        removeEventMonitors()
        interaction.reset()
        timers.scheduleCompletion(after: 0.25) { [weak self] in
            self?.close()
        }
    }

    private func scheduleTransientClose(after delay: TimeInterval) {
        schedule(after: delay) { [weak self] in
            guard let self,
                  !self.isStatusHovered,
                  !self.isPanelHovered,
                  !self.isStatusDragActive,
                  !self.isPanelDragActive else { return }
            self.close()
        }
    }

    private func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        timers.scheduleTransient(after: delay, action: action)
    }

    private func cancelPendingWork() {
        timers.cancelTransient()
    }

    private func animateOut() {
        guard panel.isVisible else {
            setAnchorHighlighted(false)
            return
        }

        animationGeneration += 1
        let generation = animationGeneration
        let restingOrigin = panel.frame.origin
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let exitOrigin = NSPoint(
            x: restingOrigin.x,
            y: restingOrigin.y + (reduceMotion ? 0 : 4)
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2,
                0,
                0,
                1
            )
            panel.animator().alphaValue = 0
            if !reduceMotion {
                panel.animator().setFrameOrigin(exitOrigin)
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.setFrameOrigin(restingOrigin)
                self.panel.alphaValue = 1
                self.setAnchorHighlighted(false)
            }
        }
    }

    private func installOutsideClickMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.closeIfPointerIsOutside()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
        }
    }

    private func installExportEndMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] event in
            self?.finishExport()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] _ in
            Task { @MainActor in self?.finishExport() }
        }
    }

    private func closeIfPointerIsOutside() {
        let pointer = NSEvent.mouseLocation
        guard !panel.frame.contains(pointer), !anchorFrame.contains(pointer) else { return }
        close()
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private var anchorFrame: NSRect {
        guard let button = anchorButton, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func setAnchorHighlighted(_ highlighted: Bool) {
        guard let button = anchorButton else { return }
        applyAnchorHighlight(highlighted, to: button)

        guard highlighted else { return }
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self,
                  let button,
                  self.anchorButton === button,
                  self.panel.isVisible else { return }
            self.applyAnchorHighlight(true, to: button)
        }
    }

    private func applyAnchorHighlight(_ highlighted: Bool, to button: NSStatusBarButton) {
        button.highlight(highlighted)
        button.isHighlighted = highlighted
        button.cell?.isHighlighted = highlighted
        button.needsDisplay = true
    }

    private func origin(relativeTo button: NSStatusBarButton) -> NSPoint {
        guard let window = button.window else {
            return centeredOrigin(on: NSScreen.main)
        }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let anchorInset: CGFloat = 28
        let leadingOrigin = buttonFrame.midX - anchorInset
        let trailingOrigin = buttonFrame.midX - panelSize.width + anchorInset
        let proposedX = leadingOrigin + panelSize.width <= visibleFrame.maxX - 8
            ? leadingOrigin
            : trailingOrigin
        let x = min(max(proposedX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let menuBarGap: CGFloat = 12
        let y = max(
            visibleFrame.minY + 8,
            buttonFrame.minY - panelSize.height - menuBarGap
        )
        return NSPoint(x: x, y: y)
    }

    private func centeredOrigin(on screen: NSScreen?) -> NSPoint {
        let frame = screen?.visibleFrame ?? .zero
        return NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.midY - panelSize.height / 2
        )
    }
}

private final class ShelfPanel: NSPanel {
    var cancelHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }
}
