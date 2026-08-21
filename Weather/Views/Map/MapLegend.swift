//
//  MapLegend.swift
//  Weather
//
//  Restores the original floating-map legend treatment for the current
//  sunny-hours map layer.
//

import SwiftUI

/// The Map's sunny-hours key uses the former Map legend's narrow vertical
/// gradient and Liquid Glass card, so its visual language stays consistent
/// with the app's earlier metric legends.
struct MapSunnyHoursLegend: View {
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

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
                .accessibilityHint("Shows the sunny-hours colour scale")
            }
        }
    }

    @ViewBuilder
    private var expandedLegend: some View {
        if reduceTransparency || colorSchemeContrast == .increased {
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
            // Match the former map legend: the close target visually hangs
            // off the trailing edge without widening the gradient scale.
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sunny hours colour scale")
    }

    /// This is the old cloud-cover gradient layout, now using the exact same
    /// quiet-to-gold endpoint colors as live sunny-hours Map dots.
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
                ForEach(["10 h+", "8 h", "6 h", "4 h", "2 h", "0 h"], id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)

                    if label != "0 h" {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 132)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
