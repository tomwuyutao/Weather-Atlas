# Weather Atlas code map

This guide is the quickest route through the project. The app uses one shared
`ContentView` state owner, with feature behavior organized into focused Swift
extensions. That keeps SwiftUI state identity in one place while preventing one
very large root-view file.

## Suggested reading order

1. `Weather/App/WeatherApp.swift` — app entry point and launch migrations.
2. `Weather/App/ThemeRoot.swift` — app-wide theme, locale, text size, contrast,
   and Reduce Motion environment.
3. `Weather/App/ContentView.swift` — root dependencies and stored SwiftUI state.
4. `Weather/App/ContentViewShell.swift` — lifecycle observers, sheets, alerts,
   and app-wide overlays.
5. `Weather/App/AppNavigation.swift` — route definitions, navigation stack, and
   route transitions.
6. The feature file you want to understand: `HomeView`, `ListView`, `MapView`,
   `DetailView`, `SettingsView`, `Tutorial`, or a search file.
7. `Weather/Helpers/WeatherService.swift` and `Weather/Models/WeatherModels.swift`
   — WeatherKit fetching and the app's weather domain data.

## Folder ownership

| Folder | Owns |
| --- | --- |
| `Weather/App` | App lifecycle, root state coordination, navigation, refresh, list selection, city saving, shortcuts, and widget publication. |
| `Weather/Views` | Screen-level SwiftUI presentation. A screen's private layout and feature-specific helpers stay with that screen. |
| `Weather/Views/Components` | Reusable presentation shared by multiple screens. |
| `Weather/Map` | Apple Maps rendering, marker/card presentation, map controls, and map-only validation. |
| `Weather/Search` | City and country search state, search services, and picker presentation. |
| `Weather/Models` | Domain values and shared data contracts. These files do not own app lifecycle. |
| `Weather/Helpers` | Services, persistence, catalogs, scoring, localization, theme infrastructure, and small cross-feature utilities. |
| `Weather/Widgets` | WidgetKit/AppIntent declarations and widget-only presentation. |

## Root-state pattern

All `@State`, `@AppStorage`, `@Environment`, `@FocusState`, and namespace values
used by `ContentView` are declared in `ContentView.swift`. Feature files extend
`ContentView` to read and mutate that shared state. When adding a feature:

- put new stored root state in `ContentView.swift` under the matching state
  section;
- put the behavior and view composition in the owning feature file;
- put a reusable visual component in `Views/Components`;
- put a reusable domain value in `Models`.

Avoid moving property-wrapper declarations merely for file size: their order is
part of the root view's state layout and keeping them together makes lifecycle
behavior easier to audit.

## Weather and persistence flow

`WeatherService` fetches WeatherKit data, resolves places/time zones, and owns
the observable weather state. Its persistence-oriented extensions are separated
by responsibility:

- `CityListStore.swift` — list identity, saved city lists, and list mutations;
- `WeatherCache.swift` — cached app forecasts;
- `PlaceResolution.swift` — canonical place and time-zone resolution;
- `WidgetCatalogPublisher.swift` — conversion from app data to the shared
  widget catalog.

Missing WeatherKit inputs use `WeatherDataIssue`; no chart, marker, or metric
should invent a replacement value. User-visible issue messages live in
`WeatherDataIssueMessages.swift`, and queued native alerts are delivered by
`DeveloperWarnings.swift`.

## App and widget shared boundary

The app and WidgetKit extension share these source files:

- `Helpers/AppPalette.swift`
- `Helpers/WidgetDataStore.swift`
- `Helpers/WidgetLocalization.swift`
- `Models/SunnyHoursTimeline.swift`
- `Models/WeatherDataIssue.swift`
- `Models/WeatherSymbols.swift`
- `Models/WidgetDataModels.swift`

`Weather/Widgets/WeatherWidgets.swift` belongs only to the widget extension.
Target membership is maintained by the synchronized-folder exception lists in
`Weather Atlas.xcodeproj/project.pbxproj`. Persisted keys, Codable field names,
widget `kind` strings, and AppIntent configuration identities must remain stable
unless an explicit migration is added.

## Comment conventions

- Every Swift file starts with its filename, target, and a one-sentence purpose.
- `// MARK:` headings describe meaningful navigator sections, not individual
  functions.
- Comments explain invariants and framework behavior: calendar/time-zone rules,
  cache freshness, WeatherKit omissions, target sharing, accessibility choices,
  or SwiftUI lifecycle ordering.
- Avoid comments that merely restate the next line of Swift.
