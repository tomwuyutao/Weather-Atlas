//
//  MapCapsule.swift
//  Weather
//
//  Purpose: Defines the compact, stateful Find Sun surface used above the Map
//  tab bar for its action, search-progress, and completed-result states.
//

import SwiftUI

// MARK: - Compact Surface

/// One compact content shell for every short-lived Map state. `MapCard` owns
/// the material and positioning; this type owns the capsule's typography,
/// spacing, Dynamic Type behavior, and interactive hit shape.
struct MapCapsule<Content: View>: View {
    let content: Content
    private let horizontalPadding: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        horizontalPadding: CGFloat = MapCardLayout.compactHorizontalPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.subheadline)
        .fontWeight(.regular)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
        .allowsTightening(true)
        .padding(.horizontal, horizontalPadding)
        .frame(
            minHeight: dynamicTypeSize.isAccessibilitySize
                ? 60
                : MapCardLayout.compactHeight
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: MapCardLayout.compactHeight / 2,
                style: .continuous
            )
        )
    }
}

// MARK: - Compact Actions

/// Icon-only action sized for the compact Map capsule.
struct MapCapsuleIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    private let iconOffsetTowardTrailing: CGFloat
    let action: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    init(
        title: LocalizedStringKey,
        systemImage: String,
        iconOffsetTowardTrailing: CGFloat = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconOffsetTowardTrailing = iconOffsetTowardTrailing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .offset(x: directionalIconOffset)
        }
        .font(.body.weight(.semibold))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    private var directionalIconOffset: CGFloat {
        layoutDirection == .leftToRight
            ? iconOffsetTowardTrailing
            : -iconOffsetTowardTrailing
    }
}

// MARK: - Search Status

/// The Find Sun search lifecycle rendered in the one shared Map capsule.
struct MapSunSearchCapsule: View {
    enum State {
        case finding(title: String)
        case results(
            title: String,
            showResults: () -> Void,
            clearResults: () -> Void
        )
    }

    let state: State

    var body: some View {
        switch state {
        case .finding(let title):
            MapCapsule {
                ProgressView()
                    .controlSize(.small)
                Text(title)
            }

        case .results(let title, let showResults, let clearResults):
            MapCapsule(horizontalPadding: 0) {
                Text(title)
                    .layoutPriority(1)
                    .padding(.leading, Layout.leadingInset)

                HStack(spacing: 0) {
                    MapCapsuleIconButton(
                        title: "Show Results",
                        systemImage: "list.bullet",
                        iconOffsetTowardTrailing: Layout.listIconOffsetTowardTrailing,
                        action: showResults
                    )

                    MapCapsuleIconButton(
                        title: "Clear Results",
                        systemImage: "xmark",
                        action: clearResults
                    )
                }
                .padding(.trailing, Layout.trailingInset)
            }
        }
    }

    private enum Layout {
        static let leadingInset: CGFloat = 20
        static let trailingInset: CGFloat = 4
        static let listIconOffsetTowardTrailing: CGFloat = 8
    }
}
