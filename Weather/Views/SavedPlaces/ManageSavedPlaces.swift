//
//  ManageSavedPlaces.swift
//  Weather
//
//  Purpose: Presents the editable Saved Places library as a compact list.
//

import SwiftUI

// MARK: - Saved Places Library

/// Full editable Saved Places library, pushed from the Saved Places dashboard.
///
/// The app shell owns the tab's `NavigationStack`; this view contributes
/// value-based links and native navigation-bar content to that stack.
struct ManageSavedPlaces: View {
    // MARK: Parent-Supplied Store and Navigation

    /// The store owns persistence. This screen creates only transient UI state,
    /// then asks the shared store to perform mutations.
    let placesStore: SavedPlacesStore

    @Bindable var router: AppNavigation

    @Environment(\.appTheme) private var theme

    // MARK: View state

    @State private var deleteAllIsPresented = false
    @State private var renamingPlace: SavedPlace?
    @State private var renameDraft = ""
    @State private var editMode: EditMode = .inactive
    @State private var presentedError: PlacesUIError?

    // MARK: Derived library data

    private var savedPlaces: [SavedPlace] { placesStore.allPlaces }

    // MARK: Screen lifecycle and navigation

    var body: some View {
        placesContent
            .environment(\.editMode, $editMode)
            .weatherScreenBackground()
            .navigationTitle("Manage Saved Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleEditMode) {
                        Image(systemName: editMode.isEditing ? "checkmark" : "pencil")
                    }

                    .disabled(savedPlaces.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete All Saved Places?",
                isPresented: $deleteAllIsPresented
            ) {
                Button("Delete All", role: .destructive) {
                    deleteAllPlaces()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every saved place. This action cannot be undone.")
            }
            .alert(
                "Unable to Update Places",
                isPresented: errorIsPresented,
                presenting: presentedError
            ) { _ in
                Button("OK") {
                    presentedError = nil
                }
            } message: { error in
                Text(error.message)
            }
            .alert(
                "Rename Saved Place",
                isPresented: renameIsPresented,
                presenting: renamingPlace
            ) { _ in
                TextField("Name", text: $renameDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                Button("Cancel", role: .cancel) {
                    endRename()
                }
                Button("Save") {
                    saveRename()
                }
                .disabled(!canSaveRename)
            } message: { place in
                Text("Leave this blank to use \(place.city.displayName).")
            }
    }

    // MARK: List states and row construction

    /// Selects the single whole-screen state: persistence failure, empty
    /// library, or the interactive list.
    @ViewBuilder
    private var placesContent: some View {
        if let loadErrorDescription = placesStore.loadErrorDescription {
            PlacesLibraryUnavailableView(
                message: loadErrorDescription,
                retry: placesStore.retryLoading
            )
        } else if savedPlaces.isEmpty {
            PlacesEmptyView(
                searchPlaces: {
                    // Do not restore a previous Search detail after the user
                    // reaches this empty-library call to action.
                    router.showSearchRoot()
                }
            )
        } else {
            placesList
        }
    }

    /// Saved places retain their persistent order. Edit mode converts each row
    /// into a direct rename control while swipe deletion stays native.
    private var placesList: some View {
        List {
            Section {
                ForEach(savedPlaces) { place in
                    placeRow(place)
                }
                .onDelete(perform: requestDeletion)
            }
            .listRowBackground(theme.colors.settingsRowFill)

            // Keep the bulk destructive action alongside the active editing
            // controls, rather than showing it during ordinary browsing.
            if editMode.isEditing {
                Section {
                    Button(role: .destructive) {
                        deleteAllIsPresented = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                            .foregroundStyle(theme.colors.destructive)
                    }
                    .tint(theme.colors.destructive)
                }
                .listRowBackground(theme.colors.settingsRowFill)
            }
        }
        .listStyle(.insetGrouped)
        .weatherScrollableBackground()
    }

    @ViewBuilder
    private func placeRow(_ place: SavedPlace) -> some View {
        if editMode.isEditing {
            HStack {
                savedPlaceRow(place)

                Spacer(minLength: 12)

                Button {
                    beginRename(place)
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.colors.primaryText)
                        // Keep this label's height intrinsic. A 44-point-tall
                        // label sits inside List's normal vertical insets and
                        // makes editing rows visibly taller than browsing rows.
                        .frame(width: 32)
                }
                .buttonStyle(.borderless)

            }
            .contextMenu { placeContextMenu(place) }
        } else {
            NavigationLink(value: AppRoute.place(id: place.id)) {
                savedPlaceRow(place)
            }
            .contextMenu { placeContextMenu(place) }
        }
    }

    private func savedPlaceRow(
        _ place: SavedPlace
    ) -> some View {
        CompactSavedPlaceRow(place: place)
    }

    // MARK: User actions and bindings

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { renamingPlace != nil },
            set: { isPresented in
                if !isPresented {
                    endRename()
                }
            }
        )
    }

    private var proposedCustomName: String? {
        SavedPlace.normalizedCustomName(renameDraft)
    }

    private var renameDraftIsValid: Bool {
        guard let proposedCustomName else { return true }
        return PlacesLibraryValidator.isValidUserFacingName(
            proposedCustomName,
            maximumLength: PlacesLibraryValidator.maximumPlaceNameLength
        )
    }

    private var canSaveRename: Bool {
        guard let renamingPlace else { return false }
        return renameDraftIsValid
            && proposedCustomName != SavedPlace.normalizedCustomName(
                renamingPlace.customName
            )
    }

    private func beginRename(_ place: SavedPlace) {
        renameDraft = place.customName ?? ""
        renamingPlace = place
    }

    private func endRename() {
        renamingPlace = nil
        renameDraft = ""
    }

    private func saveRename() {
        guard let renamingPlace, canSaveRename else { return }
        do {
            try placesStore.setCustomName(
                id: renamingPlace.id,
                customName: proposedCustomName
            )
            endRename()
        } catch {
            endRename()
            present(error)
        }
    }

    private func deleteAllPlaces() {
        do {
            try placesStore.resetToEmptyLibrary()
            editMode = .inactive
        } catch {
            present(error)
        }
    }

    private func toggleEditMode() {
        editMode = editMode.isEditing ? .inactive : .active
    }

    private func requestDeletion(_ offsets: IndexSet) {
        let placeIDs = offsets.compactMap { offset in
            savedPlaces.indices.contains(offset) ? savedPlaces[offset].id : nil
        }
        do {
            for placeID in placeIDs {
                try placesStore.deletePlace(id: placeID)
            }
        } catch {
            present(error)
        }
        leaveEditModeIfLibraryIsEmpty()
    }

    private func deletePlace(_ place: SavedPlace) {
        do {
            try placesStore.deletePlace(id: place.id)
        } catch {
            present(error)
        }
        leaveEditModeIfLibraryIsEmpty()
    }

    /// An empty library has no editable rows. Returning to the ordinary state
    /// keeps a later newly added place from inheriting stale edit controls.
    private func leaveEditModeIfLibraryIsEmpty() {
        guard savedPlaces.isEmpty else { return }
        editMode = .inactive
    }

    @ViewBuilder
    private func placeContextMenu(_ place: SavedPlace) -> some View {
        Button("Rename", systemImage: "pencil") {
            beginRename(place)
        }

        Button(role: .destructive) {
            deletePlace(place)
        } label: {
            Label("Delete", systemImage: "trash")
                .foregroundStyle(theme.colors.destructive)
        }
        .tint(theme.colors.destructive)
    }

    private func present(_ error: Error) {
        presentedError = PlacesUIError(
            message: localizedPlacesErrorDescription(error)
        )
    }
}

// MARK: - Supporting Views and Values

/// Converts an error message into an `alert(item:)`-compatible value.
private struct PlacesUIError: Identifiable {
    let id = UUID()
    let message: String
}

/// A saved-place label always uses the chosen display name as its sole title.
private struct CompactSavedPlaceRow: View {
    let place: SavedPlace

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading) {
            Text(place.displayName)
                .foregroundStyle(theme.colors.primaryText)
        }
    }
}

/// First-run state directing users toward the only way to create saved places.
private struct PlacesEmptyView: View {
    let searchPlaces: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    private var title: String {
        localizedString("No Places Yet", locale: locale)
    }

    private var description: String {
        return localizedString(
            "Save cities you care about to compare their weather in one place.",
            locale: locale
        )
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "mappin.and.ellipse")
        } description: {
            Text(description)
                .padding(.top, 12)
        } actions: {
            Button(action: searchPlaces) {
                Label("Search for a Place", systemImage: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(minHeight: 44)
            }
            .weatherGlassActionStyle()
        }
    }
}

/// Persistence failed to load, which is distinct from a legitimately empty
/// library and therefore offers a retry rather than a search call to action.
private struct PlacesLibraryUnavailableView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Places Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .weatherGlassActionStyle()
        }
    }
}
