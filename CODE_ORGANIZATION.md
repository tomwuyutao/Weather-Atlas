# Weather Atlas code organization

Weather Atlas is a native SwiftUI weather-comparison app built around one flat
**Saved Places** library. A saved city is the durable unit. There are no lists,
collections, memberships, or scoped place libraries.

## Start here

1. `Weather/App/WeatherApp.swift` creates the shared model and router, then
   installs locale, theme, text-size, and accessibility environment values.
2. `Weather/App/RootView.swift` defines the native tab shell,
   independent navigation stacks, shared routes, sheets, quick actions, widget
   deep links, and the shared forecast-date selection.
3. `Weather/App/AppRouter.swift` owns presentation state only: selected tab,
   navigation paths, modal destinations, and map selection.
4. `Weather/Models/WeatherAtlasModel.swift` coordinates saved places, place-keyed
   weather, current-location forecasts, nearest-sunny lookup, and widget
   publication.

## Native app shell

`WeatherAtlasRootView` owns one `TabView` with these destinations:

- **Home** — current-location timeline, ranked saved places, and nearest fully
  sunny catalog city.
- **Map** — an immersive map of every saved place.
- **Places** — the flat saved-place library for sorting and deleting cities.
- **Search** — a system search-role tab that finds a world city and saves it to
  Saved Places.

Home, Map, Places, and Search keep independent `NavigationStack` histories.
`AppRoute` carries stable place identity to the shared `PlaceDetailView`; root
`AppSheetDestination` values present place import and settings sheets. The
shared forecast date is selected through `TopForecastDateSwitcher`.

First launch presents the branded tutorial from `Views/Main/TutorialView.swift`.
Its final **Starting Cities** step can add a population-ranked country or
continent preset directly to Saved Places. The same bulk-add workflow is
available from Places; it never creates a grouping.

## Root state and data flow

`WeatherApp` creates `WeatherAtlasModel` and `AppRouter` once with `@State`.
`WeatherAtlasRootView` passes bindings needed by a destination and injects the
model, `PlacesStore`, `PlaceWeatherStore`, and `LocationProvider` into the
environment. Feature-local interaction state stays private to its view.

```text
PlacesStore ───────────────┐
                          ├─ WeatherAtlasModel ─ Views / widget catalog
PlaceWeatherStore ─────────┤
LocationProvider ──────────┤
WorldCitiesCatalog ────────┘
```

## Saved Places persistence

The active persistence path is:

- `Helpers/PlacesStore.swift` — the Saved Place data types, main-actor observable
  source of truth, sole mutation API, validated atomic JSON persistence, and
  schema/identity invariants for saved cities.

Historic documents that contain collection data still decode safely: Swift
`Codable` ignores those removed keys, and the next ordinary save writes the
flat current schema. The app does not expose or retain any collection model.

## Weather and recommendations

- `Helpers/Weather/PlaceWeatherStore.swift` is the observable forecast repository. It
  keys snapshots, failures, loading state, and coalesced requests by stable
  `City.ID`, and persists only disposable weather cache data.
- `Helpers/Weather/WeatherService.swift` is the WeatherKit adapter used by the
  repository.
- `Models/RecommendationEngine.swift` converts real forecasts into
  `PlaceRecommendation` values for one literal date, then groups or sorts them.
- `Helpers/Weather/SunninessScoring.swift` and the weather-domain files in `Models`
  define sunny conditions, daytime windows, and display metrics.

Home, Map, Places, and Detail request weather through `PlaceWeatherStore`; none
owns an independent forecast array. Missing WeatherKit inputs remain explicit
`WeatherDataIssue` values—views must not invent substitute chart, marker, or
ranking data.

## Current location, nearest sunny place, and search

Home keeps current-location weather separate from Saved Places. The
nearest-sunny lookup is deliberately sequential and query-budgeted:

```text
current coordinate
  → load current-location forecast
  → hide nearest-sunny card when the selected day is fully clear
  → user-selected radius
  → WorldCitiesCatalog distance ordering
  → inspect at most 10 candidates through PlaceWeatherStore
  → stop at the first exact clear-condition match
```

`LocationProvider` owns one-shot Core Location requests and display metadata.
`WeatherAtlasModel` persists the radius selected on the Home card and prevents
an identical completed lookup from rerunning when tabs rebuild. `WorldCitiesCatalog`
loads and indexes the bundled `worldcities.csv` once and performs geographic and
text queries off the main actor.

`CitySearchManager` uses the same region-neutral catalog for Search. The
selected result is reverse-geocoded for timezone metadata, then saved through
`PlacesStore`. `CountryCityCatalog` supplies the country and continent presets
used by `AddPlacesSheet` and first-run Starting Cities.

## View ownership

| Area | Primary files |
| --- | --- |
| App shell and routing | `App/RootView.swift`, `App/AppRouter.swift` |
| Recommendations | `Views/Main/HomeView.swift`, `Views/Components/CurrentLocationTimelineCard.swift`, `Views/Components/BestSunnyPlacesCard.swift`, `Views/Components/NearestSunnyPlaceCard.swift` |
| Immersive map | `Views/Main/MapView.swift` |
| Saved-place library and bulk add | `Views/Main/PlacesView.swift`, `Views/Places/AddPlacesSheet.swift` |
| Search and add | `Views/Places/PlaceSearchView.swift`, `Search/CitySearch.swift` |
| Shared date context | `Views/Components/TopForecastDateSwitcher.swift` |
| Forecast report | `Views/Main/PlaceDetailView.swift`, `Views/Main/ChartView.swift` |
| Preferences | `Views/Main/SettingsView.swift` |
| First-run tutorial | `Views/Main/TutorialView.swift` |

## Widget integration

`WeatherAtlasModel.publishWidgetCatalog` publishes one Saved Places scope
through the app-group `WidgetDataStore` contract. Its internal `all-places`
identifier remains stable so existing widget configurations continue to work;
the user-facing label is Saved Places. Widget deep links route to the current
Places tab.

The app and widget targets share only explicitly target-membered theme,
weather-domain, timeline, issue, and widget data-contract files. Widget-only UI
and timeline behavior stays under `Weather/Widgets`.

## Change rules

- Persist saved-place changes only through `PlacesStore`.
- Load or refresh forecasts only through `PlaceWeatherStore`.
- Route by stable IDs, not captured weather snapshots.
- Keep the selected forecast date as shared navigation context.
- Prefer native SwiftUI navigation, lists, forms, search, toolbars, menus,
  sheets, alerts, and MapKit controls; custom presentation should be limited to
  Weather Atlas-specific data visualization.
