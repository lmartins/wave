import AppKit
import SwiftUI

extension Color {
    static let brand = Color(red: 0x7B / 255, green: 0x6E / 255, blue: 0xF6 / 255)
}

final class WaveWindowDelegate: NSObject, NSWindowDelegate {
    var onWindowClosed: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onWindowClosed?()
        return false
    }
}

final class ConfiguratorNSView: NSView {
    private let windowDelegate = WaveWindowDelegate()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 520, height: 500)
        window.delegate = windowDelegate
    }

    func setOnWindowClosed(_ handler: (() -> Void)?) {
        windowDelegate.onWindowClosed = handler
    }
}

struct WindowConfigurator: NSViewRepresentable {
    var onWindowClosed: () -> Void

    func makeNSView(context: Context) -> ConfiguratorNSView {
        let view = ConfiguratorNSView()
        view.setOnWindowClosed(onWindowClosed)
        return view
    }

    func updateNSView(_ nsView: ConfiguratorNSView, context: Context) {
        nsView.setOnWindowClosed(onWindowClosed)
    }
}