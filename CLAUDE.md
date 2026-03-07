# Tom's Weather

A SwiftUI weather app for iOS, iPadOS, and macOS that displays 10-day forecasts for curated city lists on an interactive world map. Powered by Apple WeatherKit.

## Architecture

- **Pure SwiftUI** with platform-adaptive layouts (`#if os(macOS)` / `UIDevice.current.userInterfaceIdiom`)
- **@Observable** pattern (no Combine) — `WeatherService` and `CitySearchManager` are `@Observable` classes
- **Dark mode only** — forced via `.preferredColorScheme(.dark)`
- **Custom font** — Avenir Next throughout, via `Font.avenir(_:weight:)` helper and `.defaultFont()` environment modifier
- **Localization** — English and Chinese (`zh-Hans`), runtime-switchable via `@AppStorage("appLanguage")`. Uses `localizedString(_:locale:)` helper with `LocalizedStringResource`

## Key Files

### App Entry
- `WeatherApp.swift` — `@main`, sets locale environment, dark mode, Avenir Next font, one-time data migration

### Views
- `ContentView.swift` (~3500 lines) — Main view with all iOS/iPadOS/macOS layout logic. Contains:
  - `iOSView` — Tab-based (list + map) with floating bottom toolbar, glass effects, vertical date slider
  - `desktopView` — `NavigationSplitView` with sidebar + map detail
  - Map mode switching (minimal SVG / borders / detailed MapKit)
  - Country Overview mode — select a country, generate a grid of weather points
  - Radial Search mode — circle-based area weather search with adjustable radius
  - City list management (multiple lists, reordering, renaming, creating, deleting)
  - Search + preview city workflow
- `WeatherDetailView.swift` — Detailed city forecast card with hourly chart, 10-day grid, swipe navigation between days. Contains `HourlyTimelineChart` (Catmull-Rom spline chart) and `DayForecastBox`
- `AddCitySearchView.swift` — Full-screen city search (iOS only) using `MKLocalSearchCompleter`
- `SettingsView.swift` — Temperature unit (°C/°F), default view (list/grid), language, reset lists. Also defines `TemperatureUnit` enum

### Desktop Components
- `DesktopSidebar.swift` — Sidebar city list with search, list switcher popover, `CityRow` view
- `DesktopDateBar.swift` — Horizontal date controls with playback (auto-advance through days)

### Helpers
- `WeatherService.swift` — Core data layer. Contains:
  - `WeatherService` class — fetches from WeatherKit, caches to UserDefaults (2-hour expiry), manages multiple city lists
  - `CityListID` — list identity with built-in lists (China, Europe) + user-created lists, persisted via UserDefaults
  - Data models: `City`, `CityWeather`, `DailyForecast`, `HourlyForecast`, `ForecastDay`, `AppWeatherCondition`
  - Cache models: `CachedCityWeather`, `CachedCity`, `CachedDailyForecast`, `CachedHourlyForecast`
  - `CountryOverviewCacheManager` — disk cache for country overview grid results
  - City localization: Chinese name mappings for all default cities
- `CitySearchManager.swift` — Wraps `MKLocalSearchCompleter` for city search with coordinate resolution
- `SVGMapView.swift` — Custom Canvas-based world map renderer with:
  - Pinch-to-zoom with rubber banding, momentum drag, offset clamping
  - `WeatherMarker` overlays (card mode vs dot mode based on collision detection)
  - Auto-fit to cities, animate-to-city, reveal-on-map pulse animation
- `MapKitMapView.swift` — MapKit `Map` with SVG country overlay drawn via `MapProxy` coordinate conversion. Features:
  - `SVGProxyOverlay` — renders country shapes aligned to MapKit using two reference points
  - `AnnotationsOverlay` — weather markers positioned via `MapProxy.convert`
  - `GridPreviewOverlay` — dots showing where weather will be fetched
  - `RadialSearchCircleOverlay` — draggable radius circle
  - Corner-rounded country borders
- `GeoProjection.swift` — Web Mercator projection: geo↔SVG↔screen coordinate conversion
- `SVGPathParser.swift` — Parses `world.svg` into `CountryPath` (id, title, CGPath). Full SVG path command support (M, L, H, V, C, S, Q, T, Z + relative variants)
- `WeatherEffectsView.swift` — Animated weather effects on markers/icons: `SunGlowEffect`, `RainDropsEffect`, `SnowflakesEffect`, `CloudDriftEffect`, `WindStreaksEffect`

## Data Flow

1. On launch, `WeatherService.fetchWeatherForAllCities()` loads cached data or fetches from WeatherKit
2. Cities are stored per-list in UserDefaults (`savedCitiesList_{listID}`)
3. Weather cache stored in UserDefaults (`cachedWeatherData_{listID}`) with 2-hour expiry
4. `cityWeatherData` is the `@Observable` array driving all views
5. `selectedDayOffset` (0–9) controls which forecast day is displayed across all views

## Map System

Two map backends, selectable via `@AppStorage("mapMode")`:
- **"minimal"** (default) — Black background + SVG country fills + weather markers (uses `SVGMapView` on desktop, `MapKitMapView` with SVG overlay on iOS)
- **"borders"** — SVG country borders visible
- **"detailed"** — Standard MapKit tiles with muted emphasis

The SVG map uses `world.svg` (bundled asset) parsed into `CountryPath` objects. GeoProjection handles Web Mercator lat/lon ↔ SVG pixel conversion.

## Weather Markers

`WeatherMarker` (defined in ContentView.swift) has two display modes:
- `.card` — Shows temperature + weather icon + city name
- `.dot` — Colored dot only (when markers would overlap)

Collision detection switches all markers to dots when any two overlap on screen.

## Special Features

- **Country Overview** — Select a country on the map → generates a grid of evenly-spaced points inside the country borders → fetches weather for each → displays as a weather heatmap
- **Radial Search** — Place a circle on the map with adjustable radius → fetches weather for grid points within the circle (land only)
- **Playback** — Auto-advances through days 0–9 with 1.5s intervals
- **Glass effects** — Uses `.glassEffect()` modifier (iOS 26+)

## Conventions

- PascalCase for types, camelCase for properties/methods
- `@State private var` for SwiftUI state, `let` for constants
- 4-space indentation
- Avenir Next font family exclusively — use `Font.avenir(_:weight:)`, never system font for text
- Temperature always stored in Celsius internally, converted for display via `TemperatureUnit.display()`
- All user-facing strings go through `localizedString(_:locale:)` for runtime locale switching
- No Combine — use async/await
- `@AppStorage` for persistent user preferences
- UserDefaults for data caching (weather data, city lists)
