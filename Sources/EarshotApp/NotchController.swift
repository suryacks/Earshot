import AppKit
import SwiftUI
import EarshotKit

/// Owns the notch island window and its state machine.
///
/// The window is transparent and much larger than the island so the island can
/// animate without resizing the window every frame. Everything outside the
/// island is click-through, so the rest of the menu bar keeps working normally.
@MainActor
final class NotchController {
    private var panel: NSPanel?
    private var container: NotchContainerView?
    private var hosting: NSHostingView<NotchView>?
    private var geometry: NotchGeometry?
    private let model: AppModel

    private var state: NotchState = .idle { didSet { rebuild() } }
    private var peekTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Lifecycle

    func enable() {
        guard panel == nil, let geometry = NotchGeometry.current() else { return }
        self.geometry = geometry

        let panel = NSPanel(
            contentRect: CGRect(origin: geometry.windowOrigin, size: geometry.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Above the menu bar, so the island can cover the notch itself.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)

        let container = NotchContainerView(frame: CGRect(origin: .zero, size: geometry.windowSize))
        container.autoresizingMask = [.width, .height]
        panel.contentView = container

        self.panel = panel
        self.container = container
        rebuild()
        panel.orderFrontRegardless()
    }

    func disable() {
        peekTask?.cancel()
        hoverExitTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        container = nil
        hosting = nil
    }

    var isEnabled: Bool { panel != nil }

    /// Re-reads screen geometry, for display changes and moving between Macs.
    func screenChanged() {
        guard isEnabled else { return }
        disable()
        enable()
    }

    // MARK: - State

    private func rebuild() {
        guard let geometry, let container else { return }
        let view = NotchView(
            model: model,
            geometry: geometry,
            state: state,
            onHover: { [weak self] inside in self?.hoverChanged(inside) },
            onTap: { [weak self] in self?.tapped() })

        if let hosting {
            hosting.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
            self.hosting = hosting
        }
        container.islandRect = view.islandRect
    }

    private func hoverChanged(_ inside: Bool) {
        hoverExitTask?.cancel()
        if inside {
            guard Settings.shared.notchEnabled else { return }
            peekTask?.cancel()
            if state != .expanded { state = .expanded }
        } else {
            // A short grace period: without it, crossing a gap between two
            // subviews reads as leaving and the island flickers shut.
            hoverExitTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        }
    }

    private func collapse() {
        guard state == .expanded else { return }
        state = .idle
    }

    /// A tap anywhere on a toast or card expands the island, matching the way
    /// the phone's island behaves.
    private func tapped() {
        guard Settings.shared.notchEnabled else { return }
        peekTask?.cancel()
        state = state == .expanded ? .idle : .expanded
    }

    /// Shows the lid-open card: artwork plus per-cell battery.
    func showDevice(_ device: DeviceState, for duration: TimeInterval = 4.0) {
        present(.device(device), for: duration)
    }

    /// Shows a one-line announcement.
    func showToast(_ toast: NotchToast, for duration: TimeInterval = 2.6) {
        present(.toast(toast), for: duration)
    }

    private func present(_ next: NotchState, for duration: TimeInterval) {
        guard Settings.shared.notchEnabled, Settings.shared.notchSneakPeek, isEnabled else { return }
        // Never interrupt someone who is actively using the expanded island.
        guard state != .expanded else { return }

        peekTask?.cancel()
        state = next
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            guard self.state == next else { return }
            self.state = .idle
        }
    }
}

/// Passes clicks through everywhere except the island.
///
/// Without this the transparent window would swallow every click across the
/// top of the screen, making the menu bar unusable.
final class NotchContainerView: NSView {
    var islandRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard islandRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override var isFlipped: Bool { true }
}
