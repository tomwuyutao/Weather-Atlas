//
//  OfflineBanner.swift
//  Weather
//
//  Purpose: Defines the shared two-line offline advisory used above the tab
//  bar and inside Map's compact floating-card lane.
//

import SwiftUI

// MARK: - Shared Banner Geometry

/// Shared geometry keeps the app-level banner and Map replacement surface
/// visually equivalent even though Map supplies its own morphing glass shell.
enum OfflineBannerLayout {
    static let height: CGFloat = 62
    static let cornerRadius: CGFloat = height / 2
}

// MARK: - Floating Banner Shell

/// Full floating banner used on Your Location and Saved Places.
struct OfflineBanner: View {
    let lastUpdated: Date?
    let dismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OfflineBannerContent(
            lastUpdated: lastUpdated,
            dismiss: dismiss
        )
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: Capsule()
        )

        .foregroundStyle(theme.colors.primaryText)
    }
}

// MARK: - Shared Banner Content

/// Content shared with Map, whose `MapCard` owns the material and morphing.
struct OfflineBannerContent: View {
    let lastUpdated: Date?
    let dismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.title3.weight(.medium))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("No Internet Connection")
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .lineLimit(1)

                Text(lastUpdatedText)
                    .font(.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)

        }
        .frame(minHeight: OfflineBannerLayout.height)
    }

    private var lastUpdatedText: String {
        let time = lastUpdated?.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        ) ?? "—"
        return String(
            format: localizedString("Last updated: %@", locale: locale),
            locale: locale,
            time
        )
    }
}
