//
//  SavedNotifications.swift
//  Weather
//
//  Purpose: Presents the transient app-wide confirmation shown after a city
//  is added to or removed from Saved Places.
//

import SwiftUI

// MARK: - Notification Model

/// One successful single-city Saved Places mutation waiting to be presented.
/// A unique identity lets repeated save/remove actions animate independently.
struct SavedPlaceNotification: Identifiable, Equatable {
    enum Change: Equatable {
        case saved
        case removed
    }

    let id: UUID
    let change: Change
    let placeName: String

    init(
        id: UUID = UUID(),
        change: Change,
        placeName: String
    ) {
        self.id = id
        self.change = change
        self.placeName = placeName
    }
}

// MARK: - Liquid Glass Popup

/// Centered, noninteractive confirmation shared by every app save/unsave path.
struct SavedNotifications: View {
    let notification: SavedPlaceNotification

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: Layout.contentSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: Layout.iconSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.primaryText)

            Text(message)
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.62)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.padding)
        // A fixed 4:3 footprint keeps the popup visually consistent everywhere
        // it can be presented, while the text scales only for unusually long names.
        .frame(width: Layout.width, height: Layout.height)
        // The shared surface uses native Liquid Glass on iOS 26 and the app's
        // established material/opaque accessibility fallbacks elsewhere.
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(
                cornerRadius: Layout.cornerRadius,
                style: .continuous
            )
        )
    }

    // MARK: - Layout

    private enum Layout {
        static let width: CGFloat = 200
        static let height = width * 3 / 4
        static let iconSize: CGFloat = 36
        static let contentSpacing: CGFloat = 10
        static let padding: CGFloat = 14
        static let cornerRadius: CGFloat = 20
    }

    // MARK: - Localized Content

    private var message: String {
        switch notification.change {
        case .saved:
            localizedString(
                "Added \(notification.placeName)\nto Saved Places",
                locale: locale
            )
        case .removed:
            localizedString(
                "Removed \(notification.placeName)\nfrom Saved Places",
                locale: locale
            )
        }
    }

    private var systemImage: String {
        switch notification.change {
        case .saved: "bookmark"
        case .removed: "bookmark.slash"
        }
    }
}

#if DEBUG

// MARK: - Xcode Previews

/// A varied canvas makes the popup's translucency visible without loading any
/// live model, persistence, or weather dependency.
private struct SavedNotificationsPreviewCanvas: View {
    let notification: SavedPlaceNotification

    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    theme.colors.background,
                    theme.colors.dotSun.opacity(0.42),
                    theme.colors.rainForeground.opacity(0.30),
                    theme.colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            SavedNotifications(notification: notification)
                .padding(.horizontal, 28)
        }
    }
}

#Preview(
    "Saved Notification – Saved",
    traits: .fixedLayout(width: 390, height: 844)
) {
    SavedNotificationsPreviewCanvas(
        notification: SavedPlaceNotification(
            change: .saved,
            placeName: "London"
        )
    )
    .environment(\.appTheme, .shared)
    .preferredColorScheme(.light)
}

#Preview(
    "Saved Notification – Removed",
    traits: .fixedLayout(width: 390, height: 844)
) {
    SavedNotificationsPreviewCanvas(
        notification: SavedPlaceNotification(
            change: .removed,
            placeName: "London"
        )
    )
    .environment(\.appTheme, .shared)
    .preferredColorScheme(.light)
}

#endif
