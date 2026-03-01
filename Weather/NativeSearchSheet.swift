//
//  NativeSearchSheet.swift
//  Weather
//

import SwiftUI
import MapKit

#if !os(macOS)
// MARK: - Native Search Sheet (iOS - using native sheet presentation)
struct NativeSearchSheet: View {
    let cities: [CityWeather]
    @Binding var selectedCity: CityWeather?
    @Binding var selectedDayOffset: Int
    @Binding var isEditMode: Bool
    @Binding var searchText: String
    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?
    @State var citySearchManager: CitySearchManager
    let weatherService: WeatherService
    @Binding var selectedDetent: PresentationDetent
    let onCitySelected: (CityWeather) -> Void
    let onDeleteCity: (CityWeather) -> Void
    let onMoveCity: (IndexSet, Int) -> Void
    let onRefresh: () async -> Void
    let lastFetchDate: Date?
    let isRefreshing: Bool
    
    @State private var isLoadingSearchedCity = false
    @State private var showingAddCityView = false
    @State private var showingDatePopover = false
    @State private var previousDayOffset: Int = 0
    
    private var isMinimized: Bool {
        selectedDetent == .height(80)
    }
    
    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
    }
    
    private var dateRange: ClosedRange<Date> {
        Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date())
    }
    
    private var shortDateText: String {
        if selectedDayOffset == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }
    
    private var shortDateWithDayText: String {
        if selectedDayOffset == 0 { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, EEE"
        return formatter.string(from: selectedDate)
    }
    
    private var filteredCities: [CityWeather] {
        if searchText.isEmpty {
            return cities
        } else {
            return cities.filter { cityWeather in
                cityWeather.city.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var shouldShowSearchResults: Bool {
        !searchText.isEmpty && !citySearchManager.searchResults.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date navigation - only show when minimized
                if isMinimized {
                    HStack {
                        // Previous day button - left edge
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedDayOffset > 0 ? .primary : .tertiary)
                            .frame(width: 44, height: 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedDayOffset > 0 {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset -= 1
                                    }
                                }
                            }
                            .onLongPressGesture {
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedDayOffset = 0
                                }
                            }
                        
                        Spacer()
                        
                        // Day indicator - tappable capsule
                        Text(shortDateWithDayText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .id("minimized-date-\(selectedDayOffset)")
                            .transition(.asymmetric(
                                insertion: .move(edge: selectedDayOffset >= previousDayOffset ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: selectedDayOffset >= previousDayOffset ? .leading : .trailing).combined(with: .opacity)
                            ))
                            .frame(width: 100, height: 50)
                            .clipped()
                            .glassEffect(.regular.interactive())
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !showingDatePopover {
                                    showingDatePopover = true
                                }
                            }
                        
                        Spacer()
                        
                        // Next day button - right edge
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                            .frame(width: 44, height: 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedDayOffset < 9 {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset += 1
                                    }
                                }
                            }
                            .onLongPressGesture {
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedDayOffset = 9
                                }
                            }
                    }
                    .onChange(of: selectedDayOffset) { oldValue, _ in
                        previousDayOffset = oldValue
                    }
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
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                }
                
                // Content - only show when not minimized
                if !isMinimized {
                    if shouldShowSearchResults {
                        // Search results
                        VStack(spacing: 0) {
                            HStack {
                                Text("Search Results")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            List {
                                ForEach(citySearchManager.searchResults, id: \.title) { result in
                                    Button {
                                        Task {
                                            await selectSearchResult(result)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(result.title)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            
                                            Spacer()
                                            
                                            if isLoadingSearchedCity {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Text(result.subtitle)
                                                    .font(.headline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLoadingSearchedCity)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.visible)
                                    .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    } else if !filteredCities.isEmpty {
                        // Cities list
                        VStack(spacing: 0) {
                            // Use List in both modes, but with consistent styling
                            List {
                                ForEach(filteredCities) { cityWeather in
                                    Button {
                                        if !isEditMode {
                                            onCitySelected(cityWeather)
                                            tappedCity = cityWeather
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                showingCityDetail = true
                                                selectedDetent = .height(80)
                                            }
                                        }
                                    } label: {
                                        CityRow(
                                            cityWeather: cityWeather,
                                            dayOffset: selectedDayOffset,
                                            showCloudCover: false
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.visible)
                                    .listRowBackground(Color.clear)
                                    .contextMenu {
                                        Button {
                                            onCitySelected(cityWeather)
                                            tappedCity = cityWeather
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                showingCityDetail = true
                                                selectedDetent = .height(80)
                                            }
                                        } label: {
                                            Label("View Details", systemImage: "info.circle")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            onDeleteCity(cityWeather)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        let cityToDelete = filteredCities[index]
                                        onDeleteCity(cityToDelete)
                                    }
                                }
                                .onMove { source, destination in
                                    onMoveCity(source, destination)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                if !isMinimized {
                                    // Date picker button in toolbar when expanded
                                    Button {
                                        showingDatePopover.toggle()
                                    } label: {
                                        Text(shortDateText)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(width: 60)
                                    }
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
                                }
                            }
                            
                            ToolbarItem(placement: .principal) {
                                Text("My Cities")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {
                                    withAnimation {
                                        isEditMode.toggle()
                                    }
                                } label: {
                                    Label(isEditMode ? "Done" : "Edit", systemImage: isEditMode ? "checkmark" : "pencil")
                                }
                                
                                Button {
                                    showingAddCityView = true
                                } label: {
                                    Label("Add", systemImage: "plus")
                                }
                            }
                        }
                        .toolbarTitleDisplayMode(.inline)
                    } else {
                        Spacer()
                        Text("No cities added yet")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .navigationDestination(isPresented: $showingAddCityView) {
                AddCitySearchView(
                    cities: cities,
                    citySearchManager: CitySearchManager(),
                    weatherService: weatherService,
                    onCitySelected: { cityWeather in
                        onCitySelected(cityWeather)
                        tappedCity = cityWeather
                        showingCityDetail = true
                        showingAddCityView = false
                        selectedDetent = .height(80)
                    }
                )
            }
            .onChange(of: searchText) { oldValue, newValue in
                citySearchManager.search(query: newValue)
            }
        }
    }
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) async {
        isLoadingSearchedCity = true
        defer { isLoadingSearchedCity = false }
        
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            if let mapItem = response.mapItems.first {
                let coordinate = mapItem.location.coordinate
                let cityName = result.title
                
                if let existingCity = cities.first(where: { $0.city.name == cityName }) {
                    tappedCity = existingCity
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showingCityDetail = true
                        // Minimize the search sheet
                        selectedDetent = .height(80)
                    }
                    onCitySelected(existingCity)
                    searchText = ""
                    return
                }
                
                let tempCity = City(name: cityName, latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
                    print("⚠️ Could not fetch weather for \(cityName)")
                    return
                }
                
                tappedCity = tempCityWeather
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showingCityDetail = true
                    // Minimize the search sheet
                    selectedDetent = .height(80)
                }
                onCitySelected(tempCityWeather)
                
                searchText = ""
            }
        } catch {
            print("Error searching for location: \(error.localizedDescription)")
        }
    }
}
#endif
