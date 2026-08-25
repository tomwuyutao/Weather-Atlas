//
//  SecondaryTextActionLabel.swift
//  Weather
//
//  Purpose: Gives low-priority report navigation and library actions one
//  compact, text-only presentation without a capsule background.
//

import SwiftUI

// MARK: - Secondary Action Label

/// A quiet 44-point action label for links and non-primary mutations beneath
/// report content. The caller supplies the `Button` or `NavigationLink`.
struct SecondaryTextActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Navigation links retain their conventional trailing chevron, while
    /// place mutations use a leading icon that reads as part of the action.
    var iconIsLeading = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            if iconIsLeading {
                actionIcon
            }

            Text(title)

            if !iconIsLeading {
                actionIcon
            }
        }
        .font(.body.weight(.regular))
        .foregroundStyle(theme.colors.secondaryText)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var actionIcon: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.regular))
    }
}
