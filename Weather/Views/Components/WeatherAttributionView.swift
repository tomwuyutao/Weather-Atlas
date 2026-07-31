//
//  WeatherAttributionView.swift
//  Weather
//
//  Purpose: Presents Apple Weather's required service mark and legal link.
//

import SwiftUI
import WeatherKit

/// Apple-provided attribution mark with a native legal-page link.
struct WeatherAttributionView: View {
    let attribution: WeatherAttribution

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Link(destination: attribution.legalPageURL) {
            HStack {
                AsyncImage(url: markURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: 120,
                                maxHeight: 24,
                                alignment: .leading
                            )
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 24, minHeight: 24)
                    case .failure:
                        Text(attribution.serviceName)
                            .font(.footnote)
                    @unknown default:
                        EmptyView()
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Apple Weather legal attribution")
    }

    private var markURL: URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }
}
