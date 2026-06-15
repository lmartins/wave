import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt64
    var onRecordingChanged: ((Bool) -> Void)? = nil

    var body: some View {
        ShortcutRecorderRepresentable(
            keyCode: $keyCode,
            modifiers: $modifiers,
            onRecordingChanged: onRecordingChanged
        )
        .fixedSize()
    }
}

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt64
    var onRecordingChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            keyCode: $keyCode,
            modifiers: $modifiers,
            onRecordingChanged: onRecordingChanged
        )
    }

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        view.syncFromBindings(keyCode: keyCode, modifiers: modifiers)
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        context.coordinator.view = nsView
        nsView.syncFromBindings(keyCode: keyCode, modifiers: modifiers)
    }

    final class Coordinator {
        @Binding var keyCode: UInt16
        @Binding var modifiers: UInt64
        var onRecordingChanged: ((Bool) -> Void)?
        weak var view: ShortcutRecorderNSView?

        init(keyCode: Binding<UInt16>, modifiers: Binding<UInt64>, onRecordingChanged: ((Bool) -> Void)?) {
            _keyCode = keyCode
            _modifiers = modifiers
            self.onRecordingChanged = onRecordingChanged
        }

        func capture(keyCode: UInt16, modifiers: UInt64) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }
}

private final class ShortcutRecorderNSView: NSControl {
    weak var coordinator: ShortcutRecorderRepresentable.Coordinator?

    private static weak var activeRecorder: ShortcutRecorderNSView?

    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var isRecording = false
    private var storedKeyCode: UInt16 = 0
    private var storedModifiers: UInt64 = 0
    private var pendingKeyCode: UInt16?
    private var pendingModifiers: UInt64?
    private var currentModifierFlags: UInt64 = 0
    private var savedCombo: (keyCode: UInt16, flags: UInt64)?
    private var skipNextSync = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func syncFromBindings(keyCode: UInt16, modifiers: UInt64) {
        guard !isRecording else { return }
        if skipNextSync {
            skipNextSync = false
            return
        }
        guard keyCode != storedKeyCode || modifiers != storedModifiers else { return }
        storedKeyCode = keyCode
        storedModifiers = modifiers
        refreshLabel()
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            endRecording(cancel: true)
        } else {
            beginRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleCapturedEvent(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        handleCapturedEvent(event)
    }

    private func beginRecording() {
        Self.activeRecorder?.endRecording(cancel: true)
        Self.activeRecorder = self

        isRecording = true
        pendingKeyCode = nil
        pendingModifiers = nil
        currentModifierFlags = 0
        savedCombo = nil
        refreshChrome()
        installMonitor()
        window?.makeFirstResponder(self)
        coordinator?.onRecordingChanged?(true)
    }

    private func endRecording(cancel: Bool) {
        guard isRecording else { return }

        isRecording = false
        pendingKeyCode = nil
        pendingModifiers = nil
        removeMonitor()

        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }

        refreshChrome()
        refreshLabel()
        coordinator?.onRecordingChanged?(false)

        if cancel {
            window?.makeFirstResponder(nil)
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handleCapturedEvent(event)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        currentModifierFlags = 0
        savedCombo = nil
    }

    private func handleCapturedEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == UInt16(kVK_Delete) {
                endRecording(cancel: true)
                return
            }
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                if let combo = savedCombo {
                    commitCapture(keyCode: combo.keyCode, modifiers: combo.flags)
                }
                return
            }

            commitCapture(
                keyCode: event.keyCode,
                modifiers: captureFlags(from: event)
            )
            return
        }

        if event.type == .flagsChanged {
            let newFlags = captureFlags(from: event)
            let addedFlags = newFlags & ~currentModifierFlags
            currentModifierFlags = newFlags

            if addedFlags != 0 {
                savedCombo = (keyCode: event.keyCode, flags: newFlags)
                pendingKeyCode = event.keyCode
                pendingModifiers = newFlags
                refreshLabel()
            }
        }
    }

    private func commitCapture(keyCode: UInt16, modifiers: UInt64) {
        storedKeyCode = keyCode
        storedModifiers = modifiers
        skipNextSync = true
        coordinator?.capture(keyCode: keyCode, modifiers: modifiers)
        pendingKeyCode = nil
        pendingModifiers = nil
        refreshLabel()
        endRecording(cancel: false)
        window?.makeFirstResponder(nil)
    }

    private func captureFlags(from event: NSEvent) -> UInt64 {
        var flags: UInt64 = 0
        if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
        if event.modifierFlags.contains(.option)  { flags |= CGEventFlags.maskAlternate.rawValue }
        if event.modifierFlags.contains(.shift)   { flags |= CGEventFlags.maskShift.rawValue }
        if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
        if event.modifierFlags.contains(.function) { flags |= CGEventFlags.maskSecondaryFn.rawValue }
        return flags
    }

    private func refreshLabel() {
        let text: String
        let secondary: Bool

        if isRecording {
            if let pendingKeyCode, let pendingModifiers {
                text = KeyCodeMapping.displayString(
                    keyCode: pendingKeyCode,
                    modifiers: CGEventFlags(rawValue: pendingModifiers)
                )
                secondary = false
            } else {
                text = "Press shortcut…"
                secondary = true
            }
        } else {
            text = KeyCodeMapping.displayString(
                keyCode: storedKeyCode,
                modifiers: CGEventFlags(rawValue: storedModifiers)
            )
            secondary = false
        }

        label.stringValue = text
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
    }

    private func refreshChrome() {
        if isRecording {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    override func removeFromSuperview() {
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
        removeMonitor()
        super.removeFromSuperview()
    }
}