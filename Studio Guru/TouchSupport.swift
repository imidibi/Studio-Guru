//
//  TouchSupport.swift
//  Studio Guru
//
//  Decides whether the app should behave as it does on iPad (finger-first), and shares
//  that decision through the SwiftUI environment as `isTouchMode`.
//
//  - iPhone/iPad: always touch mode.
//  - Mac: touch mode when a touch screen is detected (macOS 27 or later), unless the user
//    overrides it in Settings.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// User override for touch mode (Mac only).
enum TouchModeSetting: String, CaseIterable, Identifiable {
    case auto
    case on
    case off

    static let storageKey = "touchModeSetting"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .on: return "Always On"
        case .off: return "Always Off"
        }
    }
}

enum TouchSupport {
    /// True if a touch screen is available.
    ///
    /// On macOS this reflects `NSScreen.touchCapabilities`. Per TN3212, the value is true for
    /// every screen while a touch-capable Sidecar display is connected, so treat it as
    /// "touch is available", not "the user is touching this display".
    @MainActor
    static var hasTouchScreen: Bool {
        #if os(macOS)
        if #available(macOS 27, *) {
            return NSScreen.screens.contains { $0.touchCapabilities.contains(.multiTouch) }
        }
        return false
        #else
        return true
        #endif
    }
}

extension EnvironmentValues {
    /// True when the app should use its finger-first (iPad) behavior.
    @Entry var isTouchMode: Bool = false
}

/// Resolves touch mode from the hardware and the user's setting, and applies it to the
/// view hierarchy. Apply once at the root of each scene.
struct TouchModeModifier: ViewModifier {
    @AppStorage(TouchModeSetting.storageKey) private var setting: TouchModeSetting = .auto
    @State private var hasTouchScreen = TouchSupport.hasTouchScreen

    private var isTouchMode: Bool {
        #if os(macOS)
        switch setting {
        case .on: return true
        case .off: return false
        case .auto: return hasTouchScreen
        }
        #else
        return true
        #endif
    }

    func body(content: Content) -> some View {
        content
            .environment(\.isTouchMode, isTouchMode)
            #if os(macOS)
            // Larger controls for fingers
            .controlSize(isTouchMode ? .large : .regular)
            // Displays can change while running (e.g. connecting a Sidecar display)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didChangeScreenParametersNotification
                )
            ) { _ in
                hasTouchScreen = TouchSupport.hasTouchScreen
            }
            #endif
    }
}

extension View {
    /// Resolves and injects `isTouchMode` for this view hierarchy.
    func touchModeAware() -> some View {
        modifier(TouchModeModifier())
    }
}
