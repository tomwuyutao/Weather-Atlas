//
//  MapLegend.swift
//  Weather
//
//  Purpose: Presents the collapsible sunny-hours scale for the Map layer.
//

import SwiftUI

// MARK: - Sunny-Hours Legend

/// A narrow vertical gradient keeps the sunny-hours scale readable without
/// obscuring the map, while the card follows the app's shared glass styling.
struct MapSunnyHoursLegend: View {
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    // MARK: - Collapsed and Expanded States

    var body: some View {
        Group {
            if isExpanded {
                expandedLegend
            } else {
                Button("Show Sunny Hours Legend", systemImage: "list.bullet.rectangle") {
                    isExpanded = true
                }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.regular))
                .foregroundStyle(theme.colors.primaryText)
                // This stays directly below the date capsule's trailing
                // chevron as a plain utility icon—not another glass button.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var expandedLegend: some View {
        if reduceTransparency {
            legendCard
                .background(theme.colors.glassFill, in: shape)
                .overlay {
                    shape.stroke(theme.colors.primaryText.opacity(0.9), lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            legendCard
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            legendCard
                .background(theme.colors.glassFill, in: shape)
                .overlay {
                    shape.stroke(theme.colors.primaryText.opacity(0.18), lineWidth: 0.6)
                }
        }
    }

    private var legendCard: some View {
        verticalGradientLegend
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            // Let the close target hang beyond the trailing edge so its full
            // hit area does not widen the compact gradient scale.
            .padding(.trailing, 20)
            .frame(width: 108, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Button("Hide Sunny Hours Legend", systemImage: "xmark") {
                    isExpanded = false
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .padding(-8)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
            .contentShape(shape)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Scale

    /// Uses the same quiet-to-gold endpoint colors as the live map dots, so
    /// the legend remains a direct key rather than an approximate guide.
    private var verticalGradientLegend: some View {
        HStack(alignment: .center, spacing: 10) {
            LinearGradient(
                colors: [10, 8, 6, 4, 2, 0].map {
                    theme.colors.sunnyHoursMapDotColor(for: Double($0))
                },
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 10, height: 132)
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 0) {
                ForEach([10, 8, 6, 4, 2, 0], id: \.self) { hours in
                    Text(
                        hours == 10
                            ? SunnyHoursFormatting.maximumHourCountLabel(
                                Double(hours),
                                locale: locale
                            )
                            : SunnyHoursFormatting.hourCountLabel(
                                Double(hours),
                                locale: locale
                            )
                    )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)

                    if hours != 0 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 132)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
