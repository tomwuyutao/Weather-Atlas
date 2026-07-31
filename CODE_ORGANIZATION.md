# Weather Atlas code organization

Weather Atlas is a native SwiftUI app built around a place-owned library.
`SavedPlace` is the durable unit; collections are optional relationships between
places. The former list-owned `ContentView` architecture is no longer the active
app shell.

## Start here

1. `Weather/App/WeatherApp.swift` creates the shared model and router, performs
   launch migrations, and installs locale, theme, text-size, and accessibility
   environment values.
2. `Weather/App/WeatherAtlasRootView.swift` defines the native tab shell,
   independent navigation stacks, shared routes, sheets, quick actions, widget
   deep links, and the shared forecast-date selection.
3. `Weather/App/AppRouter.swift` owns presentation state only: selected tab,
   navigation paths, modal destinations, collection scope, and map selection.
4. `Weather/App/WeatherAtlasModel.swift` coordinates saved places, place-keyed
   weather, nearby discovery, recommendation inputs, and widget publication.
5. Read the feature view, then the store or model that supplies its data.

## Native app shell

`WeatherAtlasRootView` owns one `TabView` with these destinations:

- **Home** — a recommendation-first list for the selected date, combining saved
  places with opted-in nearby candidates.
- **Map** — a full-screen, immersive map of the saved-place scope. It owns the
  floating date scroller, weather dots, legend, metric/filter controls, camera
  fitting, and selected-place card.
- **Places** — the list-only library for saving, sorting, searching, deleting,
  and organizing places into optional collections.
- **Search** — a system search-role tab that finds a world city and saves it
  directly to All Places.

Home, Map, Places, and Search keep independent `NavigationStack` histories.
`AppRoute` carries stable place identity and the selected literal date to the
shared `PlaceDetailView`; root-owned `AppSheetDestination` values drive add,
collection, nearby-discovery, and settings sheets.

Map and Places are sibling destinations. Do not put a list/map mode switch back
inside Places or make a collection the owner of a place.

## Root state and data flow

`WeatherApp` creates `WeatherAtlasModel` and `AppRouter` once with `@State`.
`WeatherAtlasRootView` passes bindings needed by a destination and also injects
the model, `PlacesStore`, `PlaceWeatherStore`, and `LocationProvider` into the
environment. Feature-local interaction state stays private to its view.

`AppRouter` contains no persisted domain data. `WeatherAtlasModel` coordinates
domain stores but does not duplicate their source-of-truth values:

```text
PlacesStore ───────────────┐
                          ├─ WeatherAtlasModel ─ Views / widget catalog
PlaceWeatherStore ─────────┤
LocationProvider ──────────┤
WorldCitiesCatalog ────────┘
```

## Places library

The active persistence path is:

- `Models/PlacesLibraryModels.swift` — `SavedPlace`, `PlaceCollection`, and the
  versioned `PlacesLibraryDocument`.
- `Helpers/PlacesStore.swift` — main-actor observable source of truth and the
  only mutation API for saved places, ordering, collection membership, and
  collection lifecycle.
- `Helpers/PlacesDocumentStore.swift` — validated, atomic Application Support
  JSON persistence with read-back verification.
- `Helpers/PlacesLibraryValidator.swift` — schema and relationship invariants at
  persistence boundaries.

`PlacesLibraryDocument.places` is All Places. It is never represented by a
synthetic collection. A `PlaceCollection` contains ordered place IDs, a place
may belong to multiple collections, and deleting a collection never deletes its
places.

## Weather and recommendations

- `Helpers/PlaceWeatherStore.swift` is the observable forecast repository. It
  keys snapshots, failures, loading state, and coalesced requests by stable
  `City.ID`, and persists only disposable weather cache data.
- `Helpers/WeatherService.swift` is the WeatherKit adapter used by the
  repository.
- `Models/RecommendationEngine.swift` converts real forecasts into
  `PlaceRecommendation` values for one literal date, then groups or sorts them.
- `Helpers/SunninessScoring.swift` and the weather-domain files in `Models`
  define sunny conditions, daytime windows, and display metrics.

Home, Map, Places, and Detail request weather through `PlaceWeatherStore`; none
owns an independent forecast array. Missing WeatherKit inputs remain explicit
`WeatherDataIssue` values—views must not invent substitute chart, marker, or
ranking data.

## Nearby discovery and search

Nearby discovery deliberately narrows the local dataset before WeatherKit:

```text
current coordinate
  → radius and optional current-country filter
  → WorldCitiesCatalog
  → up to 10 highest-population cities in range
  → PlaceWeatherStore
  → RecommendationEngine sunniness ranking
```

`NearbyDiscoverySettingsSheet` owns the native radius/country controls and
MapKit preview. `LocationProvider` requests permission only from an explicit
user action. `WorldCitiesCatalog` loads and indexes the bundled
`worldcities.csv` once and performs geographic and text queries off the main
actor.

`CitySearchManager` uses the same region-neutral catalog for Search. Only the
selected result is reverse-geocoded for timezone metadata; `PlaceSearchView`
then saves it through `PlacesStore` and asks `PlaceWeatherStore` to refresh it.

## View ownership

| Area | Primary files |
| --- | --- |
| App shell and routing | `App/WeatherAtlasRootView.swift`, `App/AppRouter.swift` |
| Recommendations | `Views/Main/HomeView.swift`, `Views/Components/PlaceRecommendationRow.swift` |
| Immersive map | `Views/Main/MapView.swift` |
| Places and collections | `Views/Main/PlacesView.swift`, `Views/Places/ManageCollectionsView.swift`, `Views/Places/PlaceCollectionMembershipSheet.swift` |
| Search and add | `Views/Places/PlaceSearchView.swift`, `AddPlaceSheet.swift`, `Search/CitySearch.swift` |
| Shared date context | `Views/Components/ForecastDateStrip.swift` |
| Forecast report | `Views/Main/PlaceDetailView.swift`, `Views/Main/ChartView.swift` |
| Preferences | `Views/Main/NativeSettingsView.swift`, `Views/Components/NearbyDiscoverySettingsSheet.swift` |

## Legacy and widget compatibility

`LegacyPlacesImporter` performs a read-only, one-time conversion from the former
UserDefaults list format. It deduplicates places, converts lists to optional
collections, and preserves legacy collection IDs so installed widget
configurations still resolve. The import marker is written only after the new
document is atomically saved and verified. `LegacyCityListModels` and legacy
list identities remain compatibility inputs, not active UI state.

`WeatherAtlasModel.publishWidgetCatalog` publishes All Places first, followed by
optional collections, through the existing app-group `WidgetDataStore`
contract. Widget `kind` strings, AppIntent entity identities, Codable field
names, app-group keys, and legacy deep-link formats must remain stable unless an
explicit migration is added. Old Home/Map/List quick actions and widget URLs are
translated by the root router into the current tabs and collection scopes.

The app and widget targets share only the explicitly target-membered theme,
weather-domain, timeline, issue, and widget data-contract files. Widget-only UI
and timeline behavior stays under `Weather/Widgets`.

## Change rules

- Persist place or collection changes only through `PlacesStore`.
- Load or refresh forecasts only through `PlaceWeatherStore`.
- Route by stable IDs, not captured weather snapshots.
- Keep the selected forecast date as shared navigation context.
- Prefer native SwiftUI navigation, lists, forms, search, toolbars, menus,
  sheets, alerts, and MapKit controls; custom presentation should be limited to
  Weather Atlas-specific data visualization.
