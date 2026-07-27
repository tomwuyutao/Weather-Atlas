# Weather Atlas code map

This guide is the quickest route through the project. The app uses one shared
`ContentView` state owner. Small, tightly coupled helpers stay in the source file
that owns their behavior; dedicated files are reserved for substantial screens,
services, models, or reusable components.

## Suggested reading order

1. `Weather/App/WeatherApp.swift` — app entry point, language defaults, launch
   migrations, and the root theme/locale/text-size environment.
2. `Weather/App/ContentView.swift` — root state, lifecycle observers, sheets,
   alerts, refresh work, and widget-catalog publication.
3. `Weather/App/AppNavigation.swift` — route definitions, navigation stack, and
   route transitions.
4. `Weather/Views/BottomToolbar.swift` — shared top/bottom controls, list
   switching, and forecast-date selection.
5. The feature file you want to understand: `HomeView`, `ListView`, `MapView`,
   `DetailView`, `SettingsView`, `Tutorial`, or a search file.
6. `Weather/Helpers/WeatherService.swift` and `Weather/Models/WeatherModels.swift`
   — WeatherKit fetching and the app's weather domain data.

## Folder ownership

| Folder | Owns |
| --- | --- |
| `Weather/App` | App launch, root state and shell coordination, navigation, shortcuts, refresh, and widget publication. |
| `Weather/Views` | Screen-level SwiftUI presentation, shared toolbars, map presentation, and feature-owned visual helpers. |
| `Weather/Views/Components` | The shared ranked-city row renderer in `CityCandidateRows.swift`. |
| `Weather/Search` | City and country search state, search services, and picker presentation. |
| `Weather/Models` | App weather-domain values and ranking operations. These files do not own app lifecycle. |
| `Weather/Helpers` | Services, persistence, catalogs, scoring, theme/UI infrastructure, and error presentation. |
| `Weather/Widgets` | WidgetKit/AppIntent declarations, shared app-group data contracts and persistence, and widget-only presentation. |

## Root-state pattern

All `@State`, `@AppStorage`, `@Environment`, `@FocusState`, and namespace values
used by `ContentView` are declared in `ContentView.swift`. Feature files extend
`ContentView` only when the behavior belongs to a substantial screen or domain.
When adding a feature:

- put new stored root state in `ContentView.swift` under the matching state
  section;
- put the behavior and view composition in the owning feature file;
- keep a short helper beside its call sites instead of creating a one-purpose
  file;
- put a genuinely reusable ranked-city row change in
  `Views/Components/CityCandidateRows.swift`;
- put a reusable domain value in `Models`.

Avoid moving property-wrapper declarations merely for file size: their order is
part of the root view's state layout and keeping them together makes lifecycle
behavior easier to audit.

## Weather and persistence flow

`WeatherService` fetches WeatherKit data, resolves places/time zones, and owns
the observable weather state. Persistence support is separated by responsibility:

- `CityListStore.swift` — list identity, saved city lists, and list mutations;
- `WeatherCache.swift` — cached app forecasts;
- `PlaceResolution.swift` — canonical place and time-zone resolution;
- `ContentView.swift` — conversion from loaded app data to the shared widget
  catalog.

Missing WeatherKit inputs use `WeatherDataIssue`; no chart, marker, or metric
should invent a replacement value. User-visible issue messages live in
`ErrorAlerts.swift` alongside the queued native-alert bridge and expected
forecast-omission notice.

## App and widget shared boundary

The app and WidgetKit extension share these source files:

- `Helpers/AppTheme.swift`
- `Models/SunnyHoursTimeline.swift`
- `Models/WeatherDataIssue.swift`
- `Models/WeatherSymbols.swift`
- `Widgets/WidgetDataModels.swift`
- `Widgets/WidgetDataStore.swift`

Widget-only localized-string lookup now lives directly in
`Weather/Widgets/Widgets.swift`, which belongs only to the widget extension.
Target membership is maintained by the synchronized-folder exception lists in
`Weather Atlas.xcodeproj/project.pbxproj`. Persisted keys, Codable field names,
widget `kind` strings, and AppIntent configuration identities must remain stable
unless an explicit migration is added.

## Comment conventions

- Every Swift file starts with its filename, target, and a one-sentence purpose.
- `// MARK:` headings describe meaningful navigator sections, not individual
  functions.
- Every source-level type and every stored/computed property, initializer, and
  function has a concise `///` contract comment. Property comments explain
  ownership or semantics; function comments explain the result, side effects,
  validation, or invariant rather than paraphrasing the identifier.
- Comments explain invariants and framework behavior: calendar/time-zone rules,
  cache freshness, WeatherKit omissions, target sharing, accessibility choices,
  or SwiftUI lifecycle ordering.
- Local variables and ordinary SwiftUI modifier chains remain uncommented unless
  their calculation, ordering, or framework behavior is non-obvious. This keeps
  declaration documentation complete without burying executable logic in noise.
