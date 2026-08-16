//
//  SecondaryTextActionLabel.swift
//  Weather
//
//  Purpose: Gives low-priority report navigation and library actions one
//  compact, text-only presentation without a capsule background.
//

import SwiftUI

/// A quiet 44-point action label for links and non-primary mutations beneath
/// report content. The caller supplies the `Button` or `NavigationLink`.
struct SecondaryTextActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: systemImage)
                .font(.caption.weight(.regular))
        }
        .font(.footnote.weight(.regular))
        .foregroundStyle(theme.colors.secondaryText)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
