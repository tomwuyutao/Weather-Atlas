//
//  ContentView+MapDateSlider.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI

extension ContentView {

    // MARK: - Vertical Date Slider (Map Mode)

    func mapDateSlider(height: CGFloat, transparent: Bool = false, showsSelectedLabelWhenIdle: Bool = true) -> some View {
        let totalPositions = 11 // -1 (Now) through 9
        let stepHeight = height / CGFloat(totalPositions - 1)

        // Convert between slider position (0...10) and dayOffset (-1...9)
        func positionToOffset(_ pos: Int) -> Int { pos - 1 }
        func offsetToPosition(_ offset: Int) -> Int { offset + 1 }

        let capsuleY = (isDraggingDateSlider ? sliderDragFraction * CGFloat(totalPositions - 1) : CGFloat(offsetToPosition(selectedDayOffset))) * stepHeight

        return ZStack(alignment: .topTrailing) {
            // Touch target box behind capsule — moves with it
            Color.clear
                .frame(width: selectedDayOffset > 0 ? 145 : 120, height: 80)
                .contentShape(Rectangle())
                .offset(y: capsuleY - 30)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingDateSlider {
                                sliderDragStartDay = offsetToPosition(selectedDayOffset)
                                sliderDragFraction = CGFloat(offsetToPosition(selectedDayOffset)) / CGFloat(totalPositions - 1)
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingDateSlider = true
                                }
                            }
                            let fractionalDelta = value.translation.height / height
                            let startFraction = CGFloat(sliderDragStartDay) / CGFloat(totalPositions - 1)
                            sliderDragFraction = max(0, min(1, startFraction + fractionalDelta))
                            let nearestPos = max(0, min(totalPositions - 1, Int(round(sliderDragFraction * CGFloat(totalPositions - 1)))))
                            let nearestOffset = positionToOffset(nearestPos)
                            if nearestOffset != selectedDayOffset {
                                selectedDayOffset = nearestOffset
                                PlatformFeedback.lightImpact()
                            }
                        }
                        .onEnded { _ in
                            let snappedPos = Int(round(sliderDragFraction * CGFloat(totalPositions - 1)))
                            let clampedPos = max(0, min(totalPositions - 1, snappedPos))
                            withAnimation(.smooth(duration: 0.15)) {
                                selectedDayOffset = positionToOffset(clampedPos)
                                isDraggingDateSlider = false
                            }
                        }
                )

            // Now endpoint (top)
            if isDraggingDateSlider && sliderDragFraction > 0.05 {
                sliderEndpointLabel(text: localizedString("Now", locale: locale), isWhite: false)
                    .offset(y: -4)
                    .transition(.opacity)
            }

            // Final day endpoint (bottom)
            if isDraggingDateSlider && sliderDragFraction < 0.95 {
                sliderEndpointLabel(text: sliderDateText(for: 9), isWhite: false)
                    .offset(y: height - 4)
                    .transition(.opacity)
            }

            if isDraggingDateSlider || showsSelectedLabelWhenIdle {
                let displayPos = isDraggingDateSlider
                    ? Int(round(sliderDragFraction * CGFloat(totalPositions - 1)))
                    : offsetToPosition(selectedDayOffset)
                let displayOffset = positionToOffset(max(0, min(totalPositions - 1, displayPos)))

                HStack(spacing: isDraggingDateSlider ? 6 : 3) {
                    Text(sliderDateText(for: displayOffset))
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(minWidth: isDraggingDateSlider ? 64 : 52)
                        .fixedSize()
                        .padding(.horizontal, isDraggingDateSlider ? 14 : 12)
                        .padding(.vertical, isDraggingDateSlider ? 9 : 7)
                        .themedGlass(in: .capsule)

                    Color.clear
                        .frame(width: isDraggingDateSlider ? 30 : 24, height: isDraggingDateSlider ? 20 : 16)
                        .themedGlass(in: .capsule)
                        .offset(x: isDraggingDateSlider ? 12 : 9)
                }
                .allowsHitTesting(false)
                .animation(.smooth(duration: 0.2), value: isDraggingDateSlider)
                .offset(y: capsuleY - (isDraggingDateSlider ? 10 : 8))
            }
        }
        .animation(.smooth(duration: 0.15), value: selectedDayOffset)
        .frame(height: height)
    }

    func sliderEndpointLabel(text: String, isWhite: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.shared.colors.primaryText.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .fixedSize()

            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 24, height: 16)
                .offset(x: 9)
        }
    }

    func sliderDateText(for day: Int) -> String {
        if day == -1 { return localizedString("Now", locale: locale) }
        if day == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date())
    }
}
