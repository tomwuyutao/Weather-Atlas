//
//  WeatherTopToolbar.swift
//  Weather
//
//  Purpose: Provides one fixed, safe-area-aware toolbar treatment for the
//  primary forecast screens so their title, icon actions, and date control
//  share the same alignment everywhere.
//

import SwiftUI

/// The title hierarchy used by the shared primary-screen toolbar.
enum WeatherTopToolbarTitleStyle {
    case prominent
    case compact

    fileprivate var font: Font {
        switch self {
        case .prominent:
            .largeTitle.weight(.bold)
        case .compact:
            .title3.weight(.semibold)
        }
    }
}

/// Whether the shared toolbar should provide an opaque screen backdrop.
enum WeatherTopToolbarBackgroundStyle: Equatable {
    case screen
    case transparent
}

/// A fixed-height toolbar row with flexible leading and trailing action slots.
///
/// Keeping this container outside of each screen prevents the shared forecast
/// date switcher from changing vertical position during navigation.
struct WeatherTopToolbar<Leading: View, Trailing: View>: View {
    let title: String
    let titleStyle: WeatherTopToolbarTitleStyle
    let showsTitle: Bool
    let backgroundStyle: WeatherTopToolbarBackgroundStyle

    private let leading: Leading
    private let trailing: Trailing

    @Environment(\.appTheme) private var theme

    init(
        title: String,
        titleStyle: WeatherTopToolbarTitleStyle,
        showsTitle: Bool = true,
        backgroundStyle: WeatherTopToolbarBackgroundStyle = .screen,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.titleStyle = titleStyle
        self.showsTitle = showsTitle
        self.backgroundStyle = backgroundStyle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading

            Text(title)
                .font(titleStyle.font)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .opacity(showsTitle ? 1 : 0)
                .layoutPriority(1)

            Spacer(minLength: 8)

            trailing
        }
        // Every primary screen reserves the same control row. This is what
        // keeps the date capsule's centre aligned between tab and detail views.
        .frame(minHeight: 44)
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(theme.colors.primaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background {
            (backgroundStyle == .screen ? theme.colors.background : .clear)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// A standard 44-point icon control for dismissing a pushed or presented view.
struct WeatherTopToolbarDismissButton: View {
    let systemImage: String

    @Environment(\.dismiss) private var dismiss

    init(systemImage: String = "chevron.left") {
        self.systemImage = systemImage
    }

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Applies the shared primary-screen toolbar while suppressing the native
    /// navigation bar that would otherwise introduce a different vertical grid.
    func weatherAtlasTopToolbar<Leading: View, Trailing: View>(
        title: String,
        titleStyle: WeatherTopToolbarTitleStyle,
        showsTitle: Bool = true,
        backgroundStyle: WeatherTopToolbarBackgroundStyle = .screen,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                WeatherTopToolbar(
                    title: title,
                    titleStyle: titleStyle,
                    showsTitle: showsTitle,
                    backgroundStyle: backgroundStyle,
                    leading: leading,
                    trailing: trailing
                )
            }
    }
}
