//
//  DesktopDateBar.swift
//  Weather
//

import SwiftUI

// MARK: - Desktop Date Bar (macOS & iPadOS)

struct DesktopDateBar: View {
    @Binding var selectedDayOffset: Int
    @Binding var showCloudCover: Bool
    @Binding var filterSunny: Bool
    @Binding var isPlaying: Bool
    
    @Environment(\.locale) private var locale
    @State private var showingDatePopover = false
    @State private var previousDayOffset: Int = 0
    @State private var playbackTask: Task<Void, Never>?
    
    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
    }
    
    private var dateRange: ClosedRange<Date> {
        Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date())
    }
    
    private var shortDateWithDayText: String {
        if selectedDayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: selectedDate)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Sunny filter toggle
            Button {
                filterSunny.toggle()
            } label: {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(filterSunny ? .orange : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.thickMaterial, in: Circle())
            
            // Cloud cover toggle
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    showCloudCover.toggle()
                }
            } label: {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(showCloudCover ? .blue : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.thickMaterial, in: Circle())
            
            HStack(spacing: 2) {
                // Previous day button
                Button {
                    stopPlayback()
                    if selectedDayOffset > 0 {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset -= 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedDayOffset > 0 ? .primary : .tertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    stopPlayback()
                    withAnimation(.smooth(duration: 0.3)) {
                        selectedDayOffset = 0
                    }
                })
                
                // Day indicator
                Button {
                    showingDatePopover.toggle()
                } label: {
                    Text(shortDateWithDayText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .id("desktop-date-\(selectedDayOffset)")
                        .transition(.asymmetric(
                            insertion: .move(edge: selectedDayOffset >= previousDayOffset ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: selectedDayOffset >= previousDayOffset ? .leading : .trailing).combined(with: .opacity)
                        ))
                        .frame(width: 80)
                        .clipped()
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingDatePopover) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: { newDate in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                                if let days = components.day {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset = max(0, min(9, days))
                                    }
                                }
                            }
                        ),
                        in: dateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 280, height: 300)
                    .padding(8)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.thickMaterial)
                }
                
                // Next day button
                Button {
                    stopPlayback()
                    if selectedDayOffset < 9 {
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset += 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    stopPlayback()
                    withAnimation(.smooth(duration: 0.3)) {
                        selectedDayOffset = 9
                    }
                })
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize()
            .background(.thickMaterial, in: Capsule())
            
            // Play/pause button
            Button {
                if isPlaying {
                    stopPlayback()
                } else {
                    startPlayback()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .background(.thickMaterial, in: Circle())
        }
        .onChange(of: selectedDayOffset) { oldValue, _ in
            previousDayOffset = oldValue
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
    
    private func startPlayback() {
        isPlaying = true
        // If already at the end, restart from the beginning
        if selectedDayOffset >= 9 {
            selectedDayOffset = 0
        }
        playbackTask = Task {
            while !Task.isCancelled && selectedDayOffset < 9 {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                withAnimation(.smooth(duration: 0.4)) {
                    selectedDayOffset += 1
                }
            }
            // Playback finished naturally
            if !Task.isCancelled {
                isPlaying = false
            }
        }
    }
    
    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}
