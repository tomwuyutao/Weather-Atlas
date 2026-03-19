//
//  WeatherDetailView+ChartCard.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    /// Target hour to center the entire-day chart on.
    /// "Now" mode → current city hour; other days → 10:00.
    private var entireDayScrollTargetHour: Int {
        let isNow = internalSelectedDay == -1 || internalSelectedDay == 0
        if isNow {
            var calendar = Calendar.current
            calendar.timeZone = cityWeather.timeZone
            return calendar.component(.hour, from: Date())
        }
        return 10
    }

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
                    .padding(.vertical, 6)
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
                             : chartTimeRange == .entireDay
                             ? localizedString("Entire Day", locale: locale)
                             : localizedString("10 Days", locale: locale))
                            .font(.avenir(.subheadline, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(AppTheme.shared.colors.listCardFill.mix(with: .black, by: colorScheme == .dark ? 0.25 : 0.06))
                )
                .popover(isPresented: $showingChartRangePopover, arrowEdge: .top) {
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

                    if chartTimeRange == .tenDay {
                        // 10-day mode: scrollable, ~6-7 days visible
                        ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            let dayCount = CGFloat(cityWeather.dailyForecasts.count)
                            let visibleDays: CGFloat = 6.5
                            let contentWidth = geo.size.width * (dayCount / visibleDays)
                            HStack(spacing: 0) {
                                ForEach(0..<cityWeather.dailyForecasts.count, id: \.self) { idx in
                                    Color.clear
                                        .frame(width: contentWidth / dayCount)
                                        .id(idx)
                                }
                            }
                            .overlay {
                                DailyTimelineChart(
                                    dailyForecasts: cityWeather.dailyForecasts,
                                    chartMetric: chartMetric,
                                    selectedDayOffset: internalSelectedDay,
                                    cityTimeZone: cityWeather.timeZone,
                                    lineColor: chartLineColor
                                )
                            }
                            .frame(width: contentWidth)
                        }
                        .onAppear {
                            let targetDay = internalSelectedDay == -1 ? 0 : internalSelectedDay
                            scrollProxy.scrollTo(targetDay, anchor: .center)
                        }
                        .onChange(of: internalSelectedDay) { _, newDay in
                            let targetDay = newDay == -1 ? 0 : newDay
                            withAnimation(.smooth(duration: 0.3)) {
                                scrollProxy.scrollTo(targetDay, anchor: .center)
                            }
                        }
                        } // ScrollViewReader
                        .id("daily-10day-\(chartMetric)")
                        .transition(.asymmetric(
                            insertion: .move(edge: insertEdge).combined(with: .opacity),
                            removal: .move(edge: removeEdge).combined(with: .opacity)
                        ))
                    } else if chartTimeRange == .entireDay {
                        ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                let contentWidth = max(geo.size.width * 2.5, 900)
                                let columnWidth = contentWidth / 24
                                ForEach(0..<24, id: \.self) { hour in
                                    Color.clear
                                        .frame(width: columnWidth)
                                        .id(hour)
                                }
                            }
                            .overlay {
                                HourlyTimelineChart(
                                    hourlyForecasts: forecast.hourlyForecasts,
                                    chartMetric: chartMetric,
                                    dayOffset: internalSelectedDay,
                                    cityTimeZone: cityWeather.timeZone,
                                    previewCurrentHour: previewCurrentHour,
                                    lineColor: chartLineColor,
                                    showAllHours: true
                                )
                            }
                            .frame(width: max(geo.size.width * 2.5, 900))
                        }
                        .onAppear {
                            scrollProxy.scrollTo(entireDayScrollTargetHour, anchor: .center)
                        }
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            geo.contentOffset.x <= 1
                        } action: { _, atStart in
                            chartScrollAtStart = atStart
                        }
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            geo.contentOffset.x + geo.containerSize.width >= geo.contentSize.width - 1
                        } action: { _, atEnd in
                            chartScrollAtEnd = atEnd
                        }
                        .id("hourly-all-\(internalSelectedDay)")
                        .transition(.asymmetric(
                            insertion: .move(edge: insertEdge).combined(with: .opacity),
                            removal: .move(edge: removeEdge).combined(with: .opacity)
                        ))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 50)
                                .onEnded { value in
                                    let horizontal = value.translation.width
                                    let vertical = value.translation.height
                                    guard abs(horizontal) > abs(vertical) * 2 else { return }
                                    let maxDay = cityWeather.dailyForecasts.count - 1
                                    // Swipe left at end → next day
                                    if horizontal < -120 && chartScrollAtEnd && internalSelectedDay < maxDay {
                                        swipeDirection = .forward
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            internalSelectedDay += 1
                                        }
                                        chartScrollAtStart = true
                                        chartScrollAtEnd = false
                                    }
                                    // Swipe right at start → previous day
                                    else if horizontal > 120 && chartScrollAtStart && internalSelectedDay > -1 {
                                        swipeDirection = .backward
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            internalSelectedDay -= 1
                                        }
                                        chartScrollAtStart = true
                                        chartScrollAtEnd = false
                                    }
                                }
                        )
                        } // ScrollViewReader
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
            .highPriorityGesture(
                chartTimeRange == .daytime
                ? DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            isSwipingDays = true
                        }
                    }
                    .onEnded { value in
                        isSwipingDays = false
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > abs(vertical) * 1.5 else { return }
                        let maxDay = cityWeather.dailyForecasts.count - 1
                        if horizontal < -50 && internalSelectedDay < maxDay {
                            swipeDirection = .forward
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                internalSelectedDay += 1
                            }
                        } else if horizontal > 50 && internalSelectedDay > -1 {
                            swipeDirection = .backward
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                internalSelectedDay -= 1
                            }
                        }
                    }
                : nil
            )
            .padding(.top, 8)
        }
        .background(AppTheme.shared.colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }
}
