import Foundation
import CoreGraphics
import Carbon.HIToolbox

final class HotkeyService {
    var targetKeyCode: CGKeyCode = CGKeyCode(kVK_Space)
    var targetModifiers: CGEventFlags = .maskControl
    var isToggleMode = false
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierShortcutIsPressed = false
    // Tracks which specific modifier keyCodes are currently held (distinguishes L vs R keys)
    private var heldModifierKeyCodes: Set<CGKeyCode> = []
    private var previousModifierFlags: CGEventFlags = []

    func start() {
        modifierShortcutIsPressed = false
        previousModifierFlags = []
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        modifierShortcutIsPressed = false
        heldModifierKeyCodes.removeAll()
        previousModifierFlags = []
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let relevantFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]
        let currentMods = flags.intersection(relevantFlags)
        let targetMods = targetModifiers.intersection(relevantFlags)
        let isModifierOnlyShortcut = isModifierKey(targetKeyCode)

        if isModifierOnlyShortcut {
            guard type == .flagsChanged else {
                return Unmanaged.passRetained(event)
            }

            if currentMods.rawValue > previousModifierFlags.rawValue {
                heldModifierKeyCodes.insert(keyCode)
            } else if currentMods.rawValue < previousModifierFlags.rawValue {
                heldModifierKeyCodes.remove(keyCode)
            }
            if currentMods.isEmpty { heldModifierKeyCodes.removeAll() }
            previousModifierFlags = currentMods

            // Flags must match AND the target key must actually be held
            let isPressed = currentMods == targetMods && !currentMods.isEmpty
                && heldModifierKeyCodes.contains(targetKeyCode)

            if isPressed && !modifierShortcutIsPressed {
                modifierShortcutIsPressed = true
                onKeyDown?()
                return nil
            }

            if !isPressed && modifierShortcutIsPressed {
                modifierShortcutIsPressed = false
                if !isToggleMode { onKeyUp?() }
                return nil
            }

            return Unmanaged.passRetained(event)
        }

        guard keyCode == targetKeyCode && currentMods == targetMods else {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            if isToggleMode && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return Unmanaged.passRetained(event)
            }
            onKeyDown?()
            return nil
        } else if type == .keyUp {
            if !isToggleMode { onKeyUp?() }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }

    private func isModifierKey(_ keyCode: CGKeyCode) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand, kVK_Control, kVK_RightControl, kVK_Option, kVK_RightOption, kVK_Shift, kVK_RightShift, kVK_Function:
            return true
        default:
            return false
        }
    }
}
