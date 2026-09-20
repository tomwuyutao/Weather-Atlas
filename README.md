<div align="center">
  <img src="Weather/Resources/Assets.xcassets/TutorialAppIcon.imageset/DefaultAppIcon.png" width="128" alt="Weather Atlas app icon">

# Weather Atlas

**Compare destinations by sunshine, not just by temperature or rain.**

[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0D96F6)](https://developer.apple.com/xcode/swiftui/)

</div>

Weather Atlas is a native iPhone and iPad app for planning around sunny weather. Instead of opening forecasts city by city, you can save the places you care about and compare their daytime sunny hours for a date, a weekend, or the next reliably sunny day.

## Why Weather Atlas?

Conventional weather apps are good at answering “What will the weather be here?” Travel planning often starts with a different question: “Which of these places will be sunnier when I am free?”

Weather Atlas makes that comparison the main experience. It turns hourly forecasts into clear sunny-hour timelines, ranks saved destinations, and shows nearby alternatives when somewhere else has a brighter forecast.

## Highlights

- **Sunshine-first forecasts** — see when sunshine occurs during the day, not only a daily condition or temperature range.
- **Saved Places comparisons** — rank destinations for the selected day, compare the next weekend, or find each place's next mostly sunny day.
- **Nearby sunnier places** — discover alternatives relative to the location whose forecast you are viewing.
- **Map discovery** — search globally, inspect places on the map, and explore where the forecast is brighter.
- **Detailed outlooks** — switch between daily and 10-day charts with temperature, feels-like temperature, cloud cover, rain chance, visibility, and UV information.
- **Home or current location** — location permission is optional; a chosen home location can power the same experience.
- **Widgets** — configurable Home Screen and Lock Screen views for current/home location or a saved place.
- **Offline continuity** — forecasts are normally refreshed after 30 minutes and remain available from cache for up to 24 hours while offline.
- **Localized interface** — English, German, Spanish, French, Italian, Japanese, Korean, Portuguese, Russian, Simplified Chinese, and Traditional Chinese.

## Privacy

Weather Atlas has no account system, advertising SDK, or application server. Saved places, preferences, and forecast caches stay on the device. Current-location access is optional and can be replaced with a manually selected home location.

Forecast data comes from WeatherKit, while maps and Apple place information come from MapKit. Bundled place catalogs support worldwide search and nearby-place discovery without turning the app into a user-tracking service.

## Technology

- Swift and SwiftUI
- WeatherKit
- MapKit
- Core Location
- WidgetKit and App Intents
- Swift Observation and structured concurrency
- [`SwiftTimeZoneLookup`](https://github.com/patrick-zippenfenig/SwiftTimeZoneLookup)

The app targets **iOS 18 and later**. Newer visual features such as Liquid Glass are adopted when available, with native material-based presentation retained on iOS 18.

## Running the project

1. Clone the repository:

   ```sh
   git clone https://github.com/tomwuyutao/Weather-Atlas.git
   cd Weather-Atlas
   ```

2. Open `Weather Atlas.xcodeproj` in Xcode.
3. Select your Apple Developer team for both the **Weather Atlas** and **WeatherWidgets** targets.
4. Replace the existing bundle identifiers and App Group with identifiers owned by your team.
5. Enable **WeatherKit** and the same **App Groups** capability for both targets, then update their entitlements to match.
6. Build and run on an iOS 18-or-later device or simulator.

WeatherKit requires properly configured signing and entitlements. An unsigned build can compile successfully but cannot retrieve live forecasts.

## Project structure

| Path | Responsibility |
| --- | --- |
| `Weather/App` | App lifecycle, root navigation, deep links, and system integration |
| `Weather/Models` | Forecast, place, weather-condition, and sunny-hour domain models |
| `Weather/Helpers` | Persistence, WeatherKit access, location, caching, theming, and localization |
| `Weather/Views` | Your Location, Saved Places, Map, Search, Detail, Settings, and tutorial UI |
| `Weather/Widgets` | WidgetKit extension, configuration intents, timelines, and widget layouts |
| `Weather/Resources` | App icons and bundled place catalogs |

For a guided source tour, see [CODE_ORGANIZATION.md](CODE_ORGANIZATION.md). Resource ownership and localization details are documented in [PROJECT_RESOURCES_GUIDE.md](PROJECT_RESOURCES_GUIDE.md).

## Data and attribution

Weather data is provided by Apple Weather, and maps are provided by Apple Maps. The bundled geographic datasets incorporate public data from [SimpleMaps](https://simplemaps.com/), [GeoNames](https://www.geonames.org/), and [Open-Meteo](https://open-meteo.com/).

See [ThirdPartyNotices.txt](Weather/ThirdPartyNotices.txt) for dependency and dataset notices.

## Project status

Weather Atlas is an actively developed personal project focused on making sunny-day and short-trip planning faster, clearer, and more visual.
