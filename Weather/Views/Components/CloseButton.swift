//
//  CloseButton.swift
//  Weather
//
//  Purpose: Defines the app-wide top-leading close control for dismissible
//  sheets, full-screen covers, and overlays.
//

import SwiftUI

// MARK: - Shared Close Control

/// Keeps every explicit dismissal consistent with Settings: an xmark in a
/// 44-point target at the top-leading edge of the presented surface.
struct CloseButton: View {
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button("Close", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(theme.colors.primaryText)
            .frame(width: 44, height: 44)
    }
}
