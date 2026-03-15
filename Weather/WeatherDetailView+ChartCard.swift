//
//  WeatherDetailView+ChartCard.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    // MARK: - Chart Card with Switchers

    var chartCard: some View {
        VStack(spacing: 0) {
            // Metric value + switchers
            HStack {
                Text(chartMetricCurrentValue)
                    .font(.avenir(.title3, weight: .semibold))
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.3), value: chartMetric)
                    .animation(.smooth(duration: 0.3), value: internalSelectedDay)

                Spacer()

                // Chart metric switcher
                Button {
                    showingChartMetricPopover = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: chartMetricIcon)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 16)
                        Text(chartMetricLabel)
                            .font(.avenir(.subheadline, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(AppTheme.shared.colors.listCardFill.mix(with: .black, by: colorScheme == .dark ? 0.25 : 0.06))
                )
                .popover(isPresented: $showingChartMetricPopover) {
                    chartMetricPopoverContent
                        .presentationCompactAdaptation(.popover)
                }

                // Chart time range switcher
                Button {
                    showingChartRangePopover = true
                } label: {
                    HStack(spacing: 5) {
                        Text(chartTimeRange == .daytime
                             ? localizedString("Daytime", locale: locale)
                             : localizedString("Entire Day", locale: locale))
                            .font(.avenir(.subheadline, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(AppTheme.shared.colors.listCardFill.mix(with: .black, by: colorScheme == .dark ? 0.25 : 0.06))
                )
                .popover(isPresented: $showingChartRangePopover) {
                    chartTimeRangePopoverContent
                        .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Separator
            Rectangle()
                .fill(AppTheme.shared.colors.primaryText.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 8)

            // Chart container
            GeometryReader { geo in
                ZStack {
                    let insertEdge: Edge = swipeDirection == .forward ? .trailing : .leading
                    let removeEdge: Edge = swipeDirection == .forward ? .leading : .trailing

                    if chartTimeRange == .entireDay {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HourlyTimelineChart(
                                hourlyForecasts: forecast.hourlyForecasts,
                                chartMetric: chartMetric,
                                dayOffset: internalSelectedDay,
                                cityTimeZone: cityWeather.timeZone,
                                previewCurrentHour: previewCurrentHour,
                                lineColor: chartLineColor,
                                showAllHours: true
                            )
                            .frame(width: max(geo.size.width * 2.5, 900))
                        }
                        .id("hourly-all-\(internalSelectedDay)")
                        .transition(.asymmetric(
                            insertion: .move(edge: insertEdge).combined(with: .opacity),
                            removal: .move(edge: removeEdge).combined(with: .opacity)
                        ))
                    } else {
                        HourlyTimelineChart(
                            hourlyForecasts: forecast.hourlyForecasts,
                            chartMetric: chartMetric,
                            dayOffset: internalSelectedDay,
                            cityTimeZone: cityWeather.timeZone,
                            previewCurrentHour: previewCurrentHour,
                            lineColor: chartLineColor
                        )
                        .id("hourly-\(internalSelectedDay)")
                        .transition(.asymmetric(
                            insertion: .move(edge: insertEdge).combined(with: .opacity),
                            removal: .move(edge: removeEdge).combined(with: .opacity)
                        ))
                    }
                }
                .clipped()
            }
            .frame(height: 250)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 10), including: .gesture)
            .padding(.top, 8)
        }
        .background(AppTheme.shared.colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }
}
