//
//  AppToolbar.swift
//  Weather
//
//  Purpose: Defines toolbar presentation shared by multiple app destinations,
//  including the list switcher and consistently themed menu labels.
//

import SwiftUI

// MARK: - Shared Toolbar Metrics

enum AppToolbarMetrics {
    /// Keeps SF Symbols visually consistent across top, bottom, and map controls.
    static let iconSize: CGFloat = 21
}

// MARK: - Top Toolbar Composition

extension ContentView {
    var toolbarTitle: String {
        weatherService.activeListID.localizedDisplayName(locale: locale)
    }

    func topToolbar<Accessory: View>(
        titleOverride: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            listSwitcher(titleOverride: titleOverride)
            Spacer(minLength: 12)
            accessory()
        }
        .frame(maxWidth: .infinity)
    }

    func topToolbarActionCapsule<Content: View>(
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: spacing) {
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .themedGlass(in: .capsule)
    }

    func listSwitcher(titleOverride: String?) -> some View {
        Group {
            Menu {
                ForEach(managedLists) { listID in
                    Button {
                        listEditMode = false
                        Task {
                            await switchToList(listID)
                        }
                    } label: {
                        HStack {
                            Text(listID.localizedDisplayName(locale: locale))
                                .foregroundStyle(theme.colors.primaryText)

                            Spacer()

                            if listID.rawValue == weatherService.activeListID.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.colors.primaryText)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    listEditMode = false
                    listManagementState.isPresented = true
                } label: {
                    primaryMenuLabel(
                        localizedString("Manage Lists", locale: locale),
                        systemImage: "slider.horizontal.3"
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    Text(titleOverride ?? toolbarTitle)
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    if titleOverride == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.colors.accent)
                    }
                }
            }
            .menuOrder(.fixed)
        }
    }

    // MARK: Themed Menu Content

    func primaryMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.accent)
                .tint(theme.colors.accent)
        }
        .tint(theme.colors.accent)
    }
}
