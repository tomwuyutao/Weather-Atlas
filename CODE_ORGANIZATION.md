# Weather Atlas Beta: code organization and reading guide

This document describes the source tree as it exists now. It is a guide for a
full read-through by someone who already knows programming but is new to Swift
and SwiftUI.

## The shortest mental model

Weather Atlas is a native SwiftUI weather-planning app with three primary
sections:

1. **Your Location** shows a temporary, never-saved current location and
   nearby sunny alternatives.
2. **Saved Places** compares places that the person explicitly saved.
3. **Map** shows saved places, current location, search previews, and Find Sun
   results geographically.

System Search is implemented as a fourth TabView child with SwiftUI's search
role, rather than as a normal primary tab. Widgets are a separate app
extension: they receive a small city catalog from the app and fetch their own
weather snapshots.

The central design rule is:

> Views display state. Specialized stores own persistence and forecast
> retrieval. WeatherModel coordinates app-wide workflows.

That rule explains most file boundaries.

## Swift and SwiftUI vocabulary to know first

You do not need to learn all of Swift before reading this project. These
concepts appear repeatedly:

| Term | Practical meaning in this project |
| --- | --- |
| A SwiftUI View struct | A lightweight description of UI. SwiftUI recreates descriptions often; it is not a long-lived screen controller. |
| body | The declarative UI tree returned by a view. |
| @State | Mutable state owned privately by one view, such as a selected date. |
| @Binding | A writable reference passed from a parent to a child, such as the root selected date. |
| @Observable | Modern Observation macro. SwiftUI refreshes a view when state that it read changes. |
| @Bindable | Exposes bindings to properties of an observable model or router. |
| @Environment | A dependency supplied higher in the view tree, such as locale, theme, calendar, or a shared model. |
| @MainActor | This type reads and writes UI-observed state on the main thread. |
| actor | A concurrency-isolated reference type, used here for catalog parsing and safe shared work. |
| async / await | Work that can suspend while waiting for WeatherKit, Core Location, disk, or a catalog. |
| Task | Starts asynchronous work from a synchronous SwiftUI event. |
| NavigationStack | Native push navigation. It preserves the standard interactive swipe-back gesture. |

When a line initially looks unfamiliar, first ask: is this UI state, an
observable model, a dependency injection point, or an asynchronous boundary?
That usually makes its purpose clear.

## Recommended flight reading order

Do not read the repository alphabetically. This order takes you from the app
shell to one complete user journey, then into specialised systems.

### 1. Learn the app shell

Read these in order:

1. **Weather/App/WeatherApp.swift**
2. **Weather/App/AppNavigation.swift**
3. **Weather/App/ContentView.swift**

You will learn how the app creates exactly one PlacesStore,
PlaceWeatherStore, WeatherModel, and AppNavigation; injects them into
SwiftUI; builds the tab shell; shares one selected forecast date; and handles
deep links, quick actions, settings, first-run starter places, and reset.

### 2. Learn the values that move through the app

Read:

1. **Weather/Models/WeatherModels.swift**
2. **Weather/Models/WeatherCondition.swift**
3. **Weather/Models/WeatherSymbols.swift**
4. **Weather/Models/WeatherDataValidation.swift**
5. **Weather/Models/SunnyPlacesRanking.swift**
6. **Weather/Models/SunnyHoursCalculation.swift**
7. **Weather/Models/DaylightHours.swift**
8. **Weather/Models/MapOverlayMetric.swift**

This is the best place to understand City, CityWeather, DailyForecast,
HourlyForecast, normalized weather conditions, unavailable-data reasons,
recommendations, and chart/timeline calculations. Numeric data remains in
canonical units: Celsius, kilometres, and fractions; views format it for the
user's preferences.

### 3. Learn persistence and forecast retrieval

Read:

1. **Weather/Helpers/PlacesStore.swift**
2. **Weather/Helpers/Weather/PlaceWeatherStore.swift**
3. **Weather/Helpers/Weather/WeatherService.swift**
4. **Weather/Helpers/Weather/ReverseGeocoding.swift**
5. **Weather/Helpers/Weather/WeatherCache.swift**
6. **Weather/Models/WeatherDataValidation.swift**

These files explain where data comes from, why saved places are a flat
library, which layer may write JSON, how weather is cached, how WeatherKit
values are converted to app values, and how general forecast structure is
validated without demanding a complete set of hourly timestamps.

### 4. Learn current location and nearby sun

Read:

1. **Weather/Helpers/LocationProvider.swift**
2. **Weather/Helpers/CitiesCatalog.swift**
3. **Weather/Models/WeatherModels.swift**

This is the key domain-level reading. WeatherModel is not a screen
specific view model: it coordinates the saved-place library, forecasts,
current location, calendar policy, nearby-city sampling, retention, and widget
catalog publication.

### 5. Read the normal user-facing screens

Read:

1. **Weather/Views/Components/WeatherCard.swift**
2. **Weather/Views/Components/DateSwitcher.swift**
3. **Weather/Views/YourLocation/YourLocationView.swift**
4. **Weather/Views/Components/SunnyHoursTimeline.swift**
5. **Weather/Views/YourLocation/NearbySunnyPlacesCard.swift**
6. **Weather/Views/Components/TenDaySunnyHoursTimeline.swift**
7. **Weather/Views/Detail/DetailView.swift**
8. **Weather/Views/Detail/ChartView.swift**

This shows the shared visual language and the normal path from a summary card
to a detailed report. TenDaySunnyHoursTimeline is intentionally reusable, so
location and detail reports do not create independent versions of the same
ten-day chart.

### 6. Read saved-place planning

Read:

1. **Weather/Views/SavedPlaces/SavedPlacesView.swift**
2. **Weather/Views/SavedPlaces/BestSunnyDatesCard.swift**
3. **Weather/Views/SavedPlaces/BestSunnyPlacesCard.swift**
4. **Weather/Views/SavedPlaces/ManageSavedPlaces.swift**

The overview is a planning dashboard. ManageSavedPlaces.swift is the editable saved-place
library. The current location is not included in saved-place heatmaps or
saved-place recommendations.

### 7. Read discovery and geography

Read:

1. **Weather/Views/Search/CitySearch.swift**
2. **Weather/Views/Search/SearchView.swift**
3. **Weather/Views/Map/MapCard.swift**
4. **Weather/Views/Map/MapView.swift**

Search resolves city candidates, Map previews them, and an explicit user
action saves them. MapCard owns the compact and large forms of Map's single
floating surface. MapView owns MapKit, camera control, annotations, Find Sun
state, label placement, and routing.

### 8. Finish with preferences, app integration, and widgets

Read:

1. **Weather/Helpers/AppPreferences.swift**
2. **Weather/Helpers/AppTheme.swift**
3. **Weather/Helpers/ErrorAlerts.swift**
4. **Weather/Views/Settings/Settings.swift**
5. **Weather/App/AppDelegate.swift**
6. **Weather/Widgets/WidgetDataStore.swift**
7. **Weather/Widgets/Widgets.swift**

Widgets are worth reading last because an app extension is a separate process
with its own lifecycle and forecast loading.

## Whole-app data flow

    SwiftUI views
        | read and send user actions
        v
    WeatherModel -----------------------------------> AppNavigation
        | coordinates                                  | tab, push, sheet,
        |                                              | Map handoff state
        +--> PlacesStore --------> Places JSON in Application Support
        |
        +--> PlaceWeatherStore --> WeatherService --> WeatherKit
        |          |
        |          +-------------> disposable weather cache in Caches
        |
        +--> LocationProvider --> Core Location and place metadata
        |
        +--> CitiesCatalog ------> bundled worldcities.csv
        |
        +--> WidgetDataStore --> app-group catalog --> Widget extension
                                                       |
                                                       v
                                             Widget WeatherKit snapshots

Read arrows as ownership, not necessarily as a direct call from every screen.
For example, Your Location reads WeatherModel, which delegates saved-place
storage to PlacesStore and forecasts to PlaceWeatherStore.

## App shell, navigation, and shared state

### Tabs and routes

AppNavigation owns navigation state that should survive switching tabs.

| Router value | Meaning |
| --- | --- |
| AppTab.yourLocation | The temporary local-weather experience. |
| AppTab.savedPlaces | The saved-place dashboard and its editable library. |
| AppTab.map | The geographic experience. |
| AppTab.search | The system search-role tab. |
| AppRoute.currentLocation | Pushes the detailed current-location report. |
| AppRoute.place(id:) | Pushes a detail report for a saved or temporary City ID. |
| AppRoute.savedPlacesLibrary | Pushes the editable saved-place manager. |
| AppSheetDestination.settings | The single root sheet destination today. |

Each top-level area has its own NavigationStack path:

- yourLocationPath
- savedPlacesPath
- mapPath
- searchPath

That is why opening a detail screen in one area does not replace the history
of another area. It also keeps native navigation behavior, including
interactive swipe-back, instead of imitating navigation with custom toolbar
state.

### What ContentView owns

ContentView is the integration boundary. It owns:

- one selected forecast date shared by tabs and detail screens;
- the app-wide forecast calendar, anchored to the current location time zone
  when available;
- first-run seeding of a fixed global starter list;
- reset of user-owned state and recreation of the shell;
- the root Settings sheet;
- Home Screen quick actions; and
- widget URL handling.

The selected date is rebased when the resolved current-location time zone
changes. This preserves the idea of tomorrow rather than accidentally turning
it into another calendar day because the device and location use different
time zones.

### Deep links and quick actions

AppDelegate is intentionally small. It bridges UIKit launch and Home Screen
quick-action events into the SwiftUI root. ContentView translates those events
into router state. Widget links use the Weather Atlas URL scheme and lead to
the Saved Places flow.

## Core data model and saved-place persistence

### City and forecast values

City is the stable identity for a place. It carries the information needed to
request and interpret a forecast: name, coordinates, country, optional time
zone and catalog identity. CityWeather is the aggregate returned to the rest
of the app. It contains daily and hourly forecasts, timezone information, and
the normalized values the UI needs.

DailyForecast and HourlyForecast are data values, not views. Their date helper
methods explicitly translate a selected calendar date into the forecast time
zone. This prevents a date selected in London from silently being interpreted
as the wrong local day for Tokyo.

### Saved Places: one source of truth

Saved places are a flat library, not a hierarchy of collections.

| Type | Responsibility |
| --- | --- |
| SavedPlace | Wraps City with an optional custom display name. |
| PlacesLibraryDocument | Versioned document containing the flat array. |
| PlacesDocumentStore | Reads and atomically writes the Places JSON file. |
| PlacesLibraryValidator | Rejects invalid schemas, bad fields, and duplicate places. |
| PlacesStore | Main-actor observable source of truth and mutation API. |

Only PlacesStore should change the persistent library. It exposes operations
such as save or merge, batch save, rename, delete, retry, and reset. Keeping
persistence behind that one API prevents a view from creating inconsistent
validation or duplication rules.

The JSON document lives in Application Support. Weather cache data is separate
and disposable, so removing cache data never deletes a person's saved places.

## Forecast retrieval and data-quality policy

### Weather ownership

PlaceWeatherStore owns city-keyed forecast state:

- loaded CityWeather snapshots;
- loading and failure state;
- in-flight request coordination;
- freshness checks; and
- disk cache restoration and retention.

A normal cached forecast is considered fresh for 30 minutes. Overlapping
ordinary work for the same city is coalesced; a force refresh supersedes older
work using a request token. Generic requests share a maximum of four forecast
request slots.

WeatherService is the WeatherKit adapter. It resolves place metadata, calls
WeatherKit, turns framework-specific values into the app CityWeather model,
and never invents a forecast when real data is absent. ReverseGeocoding handles
timezone and place resolution using supplied place facts, an exact-coordinate
cache, MapKit, and Core Location; it leaves unresolved metadata blank rather
than guessing it. WeatherCache holds
Codable cache mirrors rather than making the UI model itself a persistence
format.

### Sunny-hour analysis and ranking

WeatherCondition reduces the larger WeatherKit condition vocabulary to the
app weather vocabulary. WeatherSymbols classifies system symbol choices.
SunnyHoursCalculation counts the available city-local daylight hours classified
as Clear or Partly Sunny; each counts as one full sunny hour. SunnyPlacesRanking
uses that fixed count to order places. DaylightHours supplies provider-neutral
daylight bounds and formatting shared by the app and widgets, while
WeatherDataValidation contains both the forecast checks and typed issue values.
MapOverlayMetric controls only the optional metric displayed on Map; it never
changes the sunny-hours ranking. Missing hourly coverage is feature-level: it
does not make an otherwise useful city response retry or fail cache validation.

WeatherDataIssue represents honest missing or invalid weather data. ErrorAlerts
turns those cases into user-facing copy and useful diagnostics. The code
prefers an explicit unavailable state to fabricated weather.

## Current location and nearby sunny places

### Current location lifecycle

LocationProvider is a one-shot Core Location state machine:

1. It does not request permission just by being created.
2. A UI workflow requests location, or an already-authorized request is reused.
3. A valid coordinate becomes available before reverse-geocoded metadata.
4. It obtains locality/timezone metadata when possible, with a permitted
   coordinate-only fallback.
5. WeatherModel turns the coordinate into a transient City and loads
   current-location weather.

The current location is never automatically inserted into Saved Places. Its
transient City identity is deterministic from the coordinate, which lets its
forecast be retained safely during the app session.

### Nearby-sun candidate sampling

The nearby result set is designed for day-trip variety rather than a dense
list of adjacent neighbourhoods. Population only decides which catalog cities
are worth asking WeatherKit about; forecast data decides which cities are
actually recommended.

| Distance band | Candidate rule |
| --- | --- |
| Under 25 km | Excluded. This avoids neighbourhood-scale duplicates of the current location. |
| 25 to 50 km | Keep up to 5 highest-population catalog cities. |
| 50 to 200 km | Partition candidates into northeast, southeast, southwest, and northwest relative to the user. Keep up to 5 highest-population cities in each quadrant. |
| Empty outer quadrants | Unused quadrant capacity is backfilled from the remaining outer candidates globally, population first. |

The outer scan looks through up to 10,000 catalog records before selection,
but the WeatherKit budget stays bounded: at most 5 close-ring candidates plus
20 outer-ring candidates, so at most 25 forecast lookups. Nearby lookups are
deliberately sequential. This makes the external request budget predictable
and allows partial failures without throwing away successful results.

The completed candidate weather is reused when the person changes the selected
date. The app filters and ranks locally instead of re-running the nearby
search. The Home nearby card appears when the current location is not
strictly clear; nearby results may be clear or partly sunny. A strict clear
test is intentionally used where the UI says sunny.

Your Location can hand its already-loaded nearby results to Map through AppNavigation. Map
then shows those results without another WeatherKit search.

## Main screen responsibilities

| Area | Primary view files | What belongs there |
| --- | --- | --- |
| Your Location | YourLocationView.swift, SunnyHoursTimeline.swift, NearbySunnyPlacesCard.swift | Device-location lifecycle, local timeline, and nearby-sun suggestions. |
| Saved Places overview | SavedPlacesView.swift, BestSunnyDatesCard.swift, BestSunnyPlacesCard.swift | Heatmap calendar and ranked saved-place planning. |
| Saved Places library | ManageSavedPlaces.swift | Rename, delete, and browse the persistent saved library. |
| Detail | DetailView.swift, ChartView.swift | Shared full reports, reusable charts, and saved-place actions where appropriate. |
| Map | MapCard.swift, MapView.swift | Shared two-size floating surface, MapKit presentation, markers, Find Sun, and camera handling. |
| Search | SearchView.swift, CitySearch.swift | City autocomplete/geocoding, preview on Map, and explicit saving. |
| Settings | Settings.swift | Preferences, reset, and attributions. |

### Home and detail

YourLocationView.swift owns only the device-location lifecycle: permission,
coordinate refresh, pull-to-refresh, and recovery actions. The shared report
layout is composed in DetailView.swift.

SunnyHoursTimeline.swift provides the compact current-location timeline. NearbySunnyPlacesCard
renders nearby recommendations with distance formatted in the chosen unit and
can move the cached result set to Map.

DetailView.swift owns the shared DetailReportContent canvas used for both the
transient current location and a saved or discovered City. Its thin route
wrappers retain only their genuinely different source, permission, and action
logic. ChartView.swift implements supporting metric and chart content.
TenDaySunnyHoursTimeline is a shared component, keeping the ten-day sun-hours
chart logic and appearance in one place.

### Saved Places

SavedPlacesView is not the library editor. It is a concise dashboard
for comparison:

- BestSunnyDatesCard renders a heatmap-style calendar using saved places only.
- BestSunnyPlacesCard presents the best saved-place recommendations.
- A navigation action opens ManageSavedPlaces for the full editable library.

ManageSavedPlaces.swift is where persistent-place management happens. It preserves the
saved order and supports browsing, renaming, and deleting while continuing to
use PlacesStore as the only persistence authority.

## Map and Find Sun

MapView is large because it is the composition point for several independent
behaviours:

- a continuously visible MapKit map, even when no place has been saved;
- saved-place weather annotations and a current-location annotation;
- previews handed from Search;
- Home cached nearby-sun results;
- Find Sun searches;
- selection and camera movement;
- a single floating result card at any one time;
- overlay and legend state; and
- annotation-label collision avoidance.

The visible floating card has an explicit precedence so Map does not stack
multiple cards on top of each other. The label-placement logic projects
annotation coordinates into screen space and selects placements that reduce
overlap. Camera fitting also accounts for geographic edge cases such as the
international date line.

Find Sun always changes the map weather focus to sunniness. Its scopes are
separate from Home nearby-sun policy:

| Find Sun scope | Candidate sampling |
| --- | --- |
| Visible map area | Up to 25 populous cities in the visible region. |
| Near me | Up to 25 populous cities within 100 km. |
| Country | Up to 25 populous cities in the selected country. |
| Continent | Up to 25 populous cities in the selected continent. |

Map Find Sun uses its selected-date snapshot and keeps clear-condition results,
then orders results by cloud cover and daily high. It guards asynchronous
search writes with a generation value, so an older search cannot overwrite a
newer one. A Find Sun result stays transient unless the person explicitly
saves it.

## Search

CitySearchManager combines two sources:

1. Apple Maps autocomplete, resolved through MKLocalSearch and placemark
   timezone information where possible.
2. Open-Meteo geocoding, used as an additional source of city candidates.

PlaceSearchView debounces typing by 250 milliseconds, presents source results,
and lets the person preview a result on Map. The preview city is kept in
AppNavigation and registered as a transient city in WeatherModel so a detail
route remains valid for the session. Saving is an explicit action; merely
searching or previewing does not change Saved Places.

## Preferences, styling, and errors

AppPreferences defines preference domain types and formatting/localization
choices, such as temperature and distance units. AppTheme centralizes theme
state, semantic colors, shared weather-icon treatments, backgrounds, and the
liquid-glass card style. WeatherCard defines reusable card geometry and
headers, while DateSwitcher provides the shared ten-day date-selection model
and control.

SettingsView hosts preference controls, text size, theme, reset, and
attributions. It also contains the small UIKit bridge used only where SwiftUI
needs help preserving the native interactive pop gesture.

## Widgets: a separate process

The widget extension cannot assume it shares in-memory state with the main
app. The handoff is intentionally narrow:

1. WeatherModel publishes a catalog of saved-city identities, display
   labels, timezone information, and localized widget strings to the app-group
   store.
2. WidgetDataStore writes and reads that shared catalog and widget snapshots.
3. The extension fetches its own WeatherKit forecast, stores a fresh
   WidgetWeatherSnapshot, and falls back to a stale last-known-good snapshot
   only when necessary.
4. WidgetCenter reloads timelines when shared widget data changes.

The widget cache target is 30 minutes. The catalog does not pretend to be a
main-app weather snapshot: widget weather is independently fetched by the
extension. Widgets expose a configurable saved city, Home Screen widgets in
medium and large sizes, and an accessory rectangular Lock Screen widget. They
use WeatherDataIssue for truthful missing-data states and link back to the
Saved Places route.

## Complete source and configuration map

### App

| File | Role |
| --- | --- |
| Weather/App/WeatherApp.swift | Main app entry point; creates shared stores, model, router, language defaults, and theme root. |
| Weather/App/AppDelegate.swift | UIKit bridge for Home Screen quick actions. |
| Weather/App/AppNavigation.swift | Tab selection, independent navigation paths, root sheets, and Map handoffs. |
| Weather/App/ContentView.swift | Native tab shell, route destinations, shared date/calendar, and root lifecycle integration. |

### Models

| File | Role |
| --- | --- |
| Weather/Models/WeatherModels.swift | City/forecast values plus the app-wide coordinator; stores and cache remain separate helpers. |
| Weather/Models/WeatherCondition.swift | Normalized weather-condition vocabulary. |
| Weather/Models/WeatherSymbols.swift | Weather-condition symbol classification. |
| Weather/Models/WeatherDataValidation.swift | Typed unavailable-data reasons and general ten-day forecast validation. |
| Weather/Models/SunnyPlacesRanking.swift | Fixed Clear/Partly Sunny hourly ranking with deterministic ordering. |
| Weather/Models/SunnyHoursCalculation.swift | City-local daylight-hour counting, windows, and status. |
| Weather/Models/DaylightHours.swift | Shared daylight bounds, layout, segments, and formatting for the app and widgets. |
| Weather/Models/MapOverlayMetric.swift | Optional Map display metric and its map-only ordering. |

### Helpers: persistence, location, catalogs, and presentation support

| File | Role |
| --- | --- |
| Weather/Helpers/PlacesStore.swift | Saved-place document types, validation, JSON persistence, and observable library API. |
| Weather/Helpers/LocationProvider.swift | One-shot Core Location authorization, coordinate, and metadata workflow. |
| Weather/Helpers/CitiesCatalog.swift | Actor-backed bundled global city catalog, population and geographic queries, starter cities. |
| Weather/Helpers/CountryCatalog.swift | Bundled country/city metadata, country/continent options, and timezone fallback. |
| Weather/Helpers/AppPreferences.swift | User preference types and formatting/localization helpers. |
| Weather/Helpers/AppTheme.swift | Theme state, semantic styling, backgrounds, and shared view modifiers. |
| Weather/Helpers/ErrorAlerts.swift | Error-to-copy and diagnostic presentation helpers. |

### Helpers: weather

| File | Role |
| --- | --- |
| Weather/Helpers/Weather/PlaceWeatherStore.swift | Observable city-keyed forecast repository, request coordination, cache use, and retention. |
| Weather/Helpers/Weather/WeatherService.swift | WeatherKit adapter and app-model conversion. |
| Weather/Helpers/Weather/ReverseGeocoding.swift | Place and timezone resolution around WeatherKit. |
| Weather/Helpers/Weather/WeatherCache.swift | Codable weather-cache representation and disk cache mechanics. |

### Views: shared components

| File | Role |
| --- | --- |
| Weather/Views/Components/WeatherCard.swift | Shared card surface, header alignment, and standard card structure. |
| Weather/Views/Components/DateSwitcher.swift | Shared ten-day horizon and top forecast-date control. |
| Weather/Views/Components/TenDaySunnyHoursTimeline.swift | Shared ten-day sunny-hours chart. |

### Views: Your Location and Saved Places

| File | Role |
| --- | --- |
| Weather/Views/YourLocation/YourLocationView.swift | Device-location permission, refresh, and recovery wrapper. |
| Weather/Views/Components/SunnyHoursTimeline.swift | Compact daily sunny-hours timeline shared with detail reports. |
| Weather/Views/YourLocation/NearbySunnyPlacesCard.swift | Nearby sunny-city rows, distance labels, and Map handoff. |
| Weather/Views/SavedPlaces/SavedPlacesView.swift | Saved Places planning dashboard. |
| Weather/Views/SavedPlaces/BestSunnyDatesCard.swift | Saved-places-only heatmap calendar. |
| Weather/Views/SavedPlaces/BestSunnyPlacesCard.swift | Best sunny saved-place recommendations. |

### Views: Detail, Map, Places, Search, Settings

| File | Role |
| --- | --- |
| Weather/Views/Detail/DetailView.swift | Shared detailed report canvas and the place-detail route. |
| Weather/Views/Detail/ChartView.swift | Forecast metric cards and chart presentation. |
| Weather/Views/Map/MapCard.swift | Shared compact/large Map surface and every floating-card body. |
| Weather/Views/Map/MapView.swift | MapKit screen, annotations, Find Sun state, preview, selection, and camera logic. |
| Weather/Views/SavedPlaces/ManageSavedPlaces.swift | Editable full Saved Places library. |
| Weather/Views/Search/CitySearch.swift | Apple Maps and Open-Meteo city search implementation. |
| Weather/Views/Search/SearchView.swift | Debounced search UI and explicit preview/save actions. |
| Weather/Views/Settings/Settings.swift | Preferences, reset, attributions, and navigation-gesture bridge. |

### Widgets

| File | Role |
| --- | --- |
| Weather/Widgets/WidgetDataStore.swift | App-group catalog and widget snapshot persistence. |
| Weather/Widgets/Widgets.swift | Widget configuration intents, timeline provider, WeatherKit fetching, and widget views. |
| Weather/Widgets/WeatherWidgets-Info.plist | Widget extension bundle metadata. |
| Weather/Widgets/WeatherWidgets-InfoPlist.xcstrings | Localized widget extension Info.plist strings. |
| Weather/Widgets/Localizable.xcstrings | Widget-localized UI text. |
| Weather/Widgets/WeatherWidgets.entitlements | Widget extension capabilities and app-group access. |

### Resources and project configuration

| File or directory | Role |
| --- | --- |
| Weather/Resources/Cities/worldcities.csv | Bundled global city catalog for geographic and population-based candidate queries. |
| Weather/Resources/Cities/country_city_coordinates.csv | Bundled country/city metadata used by CountryCatalog. |
| Weather/Resources/Assets.xcassets | App icon, accent color, and introductory graphics. |
| Weather/Localizable.xcstrings | Main app localized strings catalog. |
| Weather/Base.lproj/InfoPlist.strings | Base Info.plist user-facing text. |
| Weather/de.lproj, en.lproj, es.lproj, fr.lproj, it.lproj, ja.lproj, ko.lproj, pt.lproj, ru.lproj, zh-Hans.lproj, zh-Hant.lproj | Localized Info.plist strings for supported languages. |
| Weather/Weather.entitlements | Main app capabilities, including WeatherKit and app-group access. |
| Weather Atlas.xcodeproj/project.pbxproj | Xcode targets, build settings, memberships, resources, and extension configuration. |
| .gitignore | Local files and build outputs excluded from version control. |

## Safe ways to change the app

Before changing code, identify the layer first:

| If you want to change... | Start reading here |
| --- | --- |
| A card visual structure | WeatherCard, the relevant card view, then AppTheme. |
| Which cities are saved | PlacesStore and ManageSavedPlaces.swift. |
| Forecast fetch/cache behavior | PlaceWeatherStore, WeatherService, WeatherCache. |
| Sunny-hour analysis or ranking | WeatherCondition, SunnyHoursCalculation, DaylightHours, and SunnyPlacesRanking. |
| Forecast structural validation | WeatherDataValidation. |
| Current-location behavior | LocationProvider and WeatherModels. |
| Nearby-sun geography or request budget | WeatherModel and CitiesCatalog. |
| Tab, push, sheet, deep-link, or Map handoff behavior | AppNavigation and ContentView. |
| Search result sourcing | CitySearch and SearchView. |
| Map markers, cards, or Find Sun | MapView, plus WeatherModel if shared state changes. |
| Widget behavior | WidgetDataStore and Widgets, then the app-group entitlements. |

For one complete end-to-end exercise, trace this path:

1. A person changes the shared date in DateSwitcher.
2. ContentView passes the binding to the active screen.
3. The screen asks WeatherModel for a forecast on that date.
4. WeatherModel reads an already-loaded CityWeather from
   PlaceWeatherStore.
5. WeatherModels converts the selected calendar day correctly for that
   forecast time zone.
6. SunnyHoursCalculation and DaylightHours derive display data, while
   SunnyPlacesRanking orders place recommendations by sunny hours.
7. A card formats that value using AppPreferences and AppTheme.

That trace covers the key architectural promise of the app: changing a day
usually reuses honest forecast data already loaded, instead of creating
duplicate UI-specific weather logic or unnecessary network work.
