//
//  CustomizeDetail.swift
//  Weather
//
//  Purpose: Provides native drag reordering for movable city-detail sections.
//

import SwiftUI

// MARK: - Detail View Customization

/// A native inset-grouped list matching Manage Saved Places. The daily sunny
/// timeline is shown separately because it remains pinned below the city hero.
struct CustomizeDetail: View {
  @AppStorage(DetailReportSection.storageKey)
  private var storedOrder = DetailReportSection.defaultStorageValue

  @Environment(\.appTheme) private var theme
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      sectionList
        .weatherContentColumn(standardMaximumWidth: .infinity)
        .weatherScreenBackground()
        .navigationTitle("Customize Detail View")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            CloseButton(action: dismiss.callAsFunction)
          }
        }
    }
    .presentationDragIndicator(.visible)
  }

  private var sectionList: some View {
    List {
      Section {
        HStack(spacing: 12) {
          Label("Daily Sunny Hours", systemImage: "sun.max")
            .foregroundStyle(theme.colors.primaryText)

          Spacer(minLength: 8)

          Image(systemName: "pin.fill")
            .foregroundStyle(theme.colors.secondaryText)
        }
      }
      .listRowBackground(theme.colors.settingsRowFill)

      Section {
        ForEach((DetailReportSection.order(from: storedOrder))) { section in
          Label(
            {
              switch section {
              case .tenDaySunnyHours: "10-Day Sunny Hours"
              case .basicWeatherData: "Basic Weather Data"
              case .nearbySunnyPlaces: "Nearby Sunnier Places"
              }
            }(),
            systemImage: {
              switch section {
              case .tenDaySunnyHours: "calendar"
              case .basicWeatherData: "square.grid.2x2"
              case .nearbySunnyPlaces: "location.magnifyingglass"
              }
            }()
          )
          .foregroundStyle(theme.colors.primaryText)
        }
        .onMove { source, destination in
          var reorderedSections = DetailReportSection.order(from: storedOrder)
          reorderedSections.move(
            fromOffsets: source,
            toOffset: destination
          )
          storedOrder = reorderedSections.map(\.rawValue).joined(separator: ",")
        }
      }
      .listRowBackground(theme.colors.settingsRowFill)
    }
    .listStyle(.insetGrouped)
    .environment(\.editMode, .constant(.active))
    .weatherScrollableBackground()
  }

}

#if DEBUG

  #Preview("Customize Detail View") {
    CustomizeDetail()
  }
#endif
