import AppKit
import SwiftUI
import EarshotKit

/// The lid-open heads-up display.
///
/// A non-activating panel: showing battery must never steal focus from what
/// the user is typing into. It floats above full-screen apps and dismisses
/// itself, so it behaves like a system HUD rather than a window.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(device: DeviceState, for duration: TimeInterval = 4.5) {
        dismissTask?.cancel()

        let view = HUDView(device: device)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 150)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(hosting.frame.size)
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Exposed for `--selftest`.
    var debugPanel: NSPanel? { panel }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Keep it visible over full-screen apps without switching Spaces.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    /// Top-centre of whichever screen holds the pointer, inset below the menu
    /// bar (and the notch on the Macs that have one).
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 12
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}

/// Fallback card for when the island is switched off, or the Mac has no notch
/// and the user preferred a floating HUD.
private struct HUDView: View {
    let device: DeviceState
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 5) {
                DeviceArt.view(for: device, size: 48, tint: .primary.opacity(0.9))
                if device.caseBattery != nil {
                    CaseArt(size: 24, tint: .primary.opacity(0.7), lit: device.caseCharging)
                }
            }
            .frame(width: 58)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)

            VStack(alignment: .leading, spacing: 12) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                DeviceBatteries(device: device, ringSize: 44)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 320, height: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { withAnimation(Theme.morph) { appeared = true } }
    }
}
