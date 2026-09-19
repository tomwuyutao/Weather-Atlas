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
  // MARK: - Parent-Supplied Store and Navigation

  /// The store owns persistence. This screen creates only transient UI state,
  /// then asks the shared store to perform mutations.
  let placesStore: SavedPlacesStore

  @Bindable var router: AppNavigation

  @Environment(\.appTheme) private var theme
  /// App-selected locale used for mutation error recovery copy.
  @Environment(\.locale) private var locale

  // MARK: - View State

  @State private var deleteAllIsPresented = false
  @State private var renamingPlace: SavedPlace?
  @State private var renameDraft = ""
  @State private var editMode: EditMode = .inactive
  @State private var presentedError: PlacesUIError?

  // MARK: - Derived Library Data

  private var savedPlaces: [SavedPlace] { placesStore.allPlaces }

  // MARK: - Screen Lifecycle and Navigation

  var body: some View {
    placesContent
      .weatherContentColumn(standardMaximumWidth: .infinity)
      .environment(\.editMode, $editMode)
      .weatherScreenBackground()
      .navigationTitle("Manage Saved Places")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            editMode = editMode.isEditing ? .inactive : .active
          } label: {
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
          do {
            try placesStore.persist(.empty)
            placesStore.pendingSavedPlaceNotifications.removeAll()
            editMode = .inactive
          } catch {
            presentedError = PlacesUIError(
              message: localizedPlacesErrorDescription(error, locale: locale)
            )
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This removes every saved place. This action cannot be undone.")
      }
      .alert(
        "Unable to Update Places",
        isPresented: (Binding(
          get: { presentedError != nil },
          set: { isPresented in
            if !isPresented {
              presentedError = nil
            }
          }
        )),
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
        isPresented: (Binding(
          get: { renamingPlace != nil },
          set: { isPresented in
            if !isPresented {
              renamingPlace = nil
              renameDraft = ""
            }
          }
        )),
        presenting: renamingPlace
      ) { _ in
        TextField("Name", text: $renameDraft)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()

        Button("Cancel", role: .cancel) {
          renamingPlace = nil
          renameDraft = ""
        }
        Button("Save") {
          saveRename()
        }
        .disabled(!canSaveRename)
      } message: { place in
        Text("Leave this blank to use \(place.city.displayName).")
      }
  }

  // MARK: - List States and Row Construction

  /// Selects the single whole-screen state: persistence failure, empty
  /// library, or the interactive list.
  @ViewBuilder
  private var placesContent: some View {
    if placesStore.loadErrorDescription != nil {
      PlacesLibraryUnavailableView(
        retry: placesStore.retryLoading
      )
    } else if savedPlaces.isEmpty {
      PlacesEmptyView(
        searchPlaces: {
          // Do not restore a previous Search detail after the user
          // reaches this empty-library call to action.
          router.searchPath = []
          router.selectedTab = .search
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
        CompactSavedPlaceRow(place: place)

        Spacer(minLength: 12)

        Button {
          renameDraft = place.customName ?? ""
          renamingPlace = place
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
        CompactSavedPlaceRow(place: place)
      }
      .contextMenu { placeContextMenu(place) }
    }
  }

  // MARK: - User Actions and Bindings

  private var canSaveRename: Bool {
    guard let renamingPlace else { return false }
    return
      ({
        guard
          let proposedCustomName = SavedPlace.normalizedCustomName(
            renameDraft
          )
        else { return true }
        return PlacesLibraryValidator.isValidUserFacingName(
          proposedCustomName,
          maximumLength: PlacesLibraryValidator.maximumPlaceNameLength
        )
      })()
      && SavedPlace.normalizedCustomName(renameDraft)
        != SavedPlace.normalizedCustomName(
          renamingPlace.customName
        )
  }

  private func saveRename() {
    guard let place = renamingPlace, canSaveRename else { return }
    do {
      try placesStore.setCustomName(
        id: place.id,
        customName: SavedPlace.normalizedCustomName(renameDraft)
      )
      renamingPlace = nil
      renameDraft = ""
    } catch {
      renamingPlace = nil
      renameDraft = ""
      presentedError = PlacesUIError(
        message: localizedPlacesErrorDescription(error, locale: locale)
      )
    }
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
      presentedError = PlacesUIError(
        message: localizedPlacesErrorDescription(error, locale: locale)
      )
    }
    if savedPlaces.isEmpty {
      editMode = .inactive
    }
  }

  @ViewBuilder
  private func placeContextMenu(_ place: SavedPlace) -> some View {
    Button("Rename", systemImage: "pencil") {
      renameDraft = place.customName ?? ""
      renamingPlace = place
    }

    Button(role: .destructive) {
      do {
        try placesStore.deletePlace(id: place.id)
      } catch {
        presentedError = PlacesUIError(
          message: localizedPlacesErrorDescription(error, locale: locale)
        )
      }
      if savedPlaces.isEmpty {
        editMode = .inactive
      }
    } label: {
      Label("Delete", systemImage: "trash")
        .foregroundStyle(theme.colors.destructive)
    }
    .tint(theme.colors.destructive)
  }

}

#if DEBUG

  // MARK: - Preview

  #Preview("Manage Saved Places") {
    ManageSavedPlacesRoutePreview()
  }
#endif

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

  var body: some View {
    ContentUnavailableView {
      Label((localizedString("No Places Yet", locale: locale)), systemImage: "mappin.and.ellipse")
    } description: {
      Text(
        ({ () -> String in

          return localizedString(
            "Save cities you care about to compare their weather in one place.",
            locale: locale
          )
        }())
      )
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
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Places Unavailable", systemImage: "exclamationmark.triangle")
    } description: {
      Text("Saved Places could not be loaded. Try again.")
    } actions: {
      Button("Try Again", systemImage: "arrow.clockwise", action: retry)
        .weatherGlassActionStyle()
    }
  }
}
