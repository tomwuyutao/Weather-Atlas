# Project Resources Guide

This is the inventory for the non-Swift source resources in Weather Atlas. It explains what each resource contains, which target or tool owns it, and the correct place to edit it.

## Read This First: Source Resources Are Not Build Artifacts

Every path listed below is checked-in source material. Xcode consumes it during a build; it is not a runtime cache and the app never writes back to it.

| Source family | What Xcode produces | Why not edit the build output |
| --- | --- | --- |
| Weather/Resources/Cities/*.csv | A copied file in the installed main-app bundle | A copied bundle resource is replaced at the next build. Edit the repository CSV. |
| Weather/Resources/Assets.xcassets/** | A compiled asset catalog, commonly Assets.car, in a built bundle | Assets.car is generated from manifests and PNG source art. Edit the catalog source instead. |
| *.xcstrings | Localized resources inside the built app or widget bundle | The build result is regenerated from the String Catalog. Edit the catalog source. |
| *.lproj/InfoPlist.strings | A localized Info.plist strings resource in the built main-app bundle | The installed copy is regenerated and may be overwritten by Xcode. Edit the tracked .strings file. |

Examples of generated build artifacts are DerivedData, build directories, .app bundles, .appex bundles, .xcarchive bundles, Assets.car, and copied resources within those products. They are not product-source files and should never be hand-edited.

## Ownership Model

| Owner | Responsibility |
| --- | --- |
| Weather Atlas main app | Bundled city datasets, main-app localized UI copy, localized app name, and location-permission text. |
| WeatherWidgets extension | Widget-specific UI copy and its localized bundle-name copy. It reads shared runtime data but does not own the city CSV source files. |
| Xcode asset catalog compiler | Compiles asset manifests and PNG source art into the installable bundle. |
| Xcode localization pipeline | Compiles String Catalog and InfoPlist.strings source records into bundle-localized resources. |

## City Data Sources

The two CSVs are static, read-only input datasets for the main app. They are not Saved Places data, user preferences, or a weather cache.

### Weather/Resources/Cities/worldcities.csv

Role and owner:
- Owner: the main app, through CitiesCatalog.
- Role: worldwide place search and the population-first nearby-sun candidate pool.
- Widget ownership: none; the widget extension does not load this file.

Format:
- Quoted CSV with 49,992 data rows and 242 countries in the audited source.
- Coordinate range: latitude -54.9341...81.7167; longitude -179.6...179.3667.
- The exact header order is:
  city, city_ascii, lat, lng, country, iso2, iso3, admin_name, capital, population, id.

| Column | Meaning |
| --- | --- |
| city | Dataset display name for the city. |
| city_ascii | ASCII alternate name, when supplied. |
| lat / lng | WGS-84 decimal-degree coordinates. |
| country | Human-readable country or territory. |
| iso2 / iso3 | ISO country codes. |
| admin_name | Administrative area, when supplied. |
| capital | Capital classification, when supplied. |
| population | Population used for candidate selection; some source rows intentionally omit it. |
| id | Stable dataset record identifier. |

Editing rule:
- Do not edit a copy in a built app bundle. It will be discarded on rebuild.
- Do not split lines with a naive comma parser; quoted CSV values require CSV-aware parsing.
- Do not treat city names as globally unique. Preserve the stable id and country context.
- Preserve the header/schema if replacing the source; the loader validates it.

### Weather/Resources/Cities/country_city_coordinates.csv

Role and owner:
- Owner: the main app, through CountryCatalog.
- Role: country/continent discovery that also needs a valid IANA timezone for a place.
- Widget ownership: none; widgets resolve their configured city through shared runtime data.

Format:
- CSV with 4,300 data rows, 242 countries, 311 distinct IANA timezones, and no missing fields in the audited source.
- Coordinate range: latitude -54.2833...81.7167; longitude -178.1585...179.3667.
- Exact header:
  city, country, iso2, latitude, longitude, time_zone, population.

| Column | Meaning |
| --- | --- |
| city | City display name. |
| country | Human-readable country or territory. |
| iso2 | ISO two-letter country code. |
| latitude / longitude | WGS-84 decimal-degree coordinates. |
| time_zone | IANA timezone identifier, such as Europe/Andorra. |
| population | Numeric population used to order/select city records. |

Editing rule:
- Edit the repository CSV, never its copied bundle counterpart.
- Keep time_zone as a valid IANA identifier; the loader rejects invalid timezones to avoid showing the wrong local forecast date.
- Preserve UTF-8, the existing column names, and the column order.

## Xcode Asset Catalog

Weather/Resources/Assets.xcassets is source input for Xcode's asset catalog compiler. A folder ending in .appiconset, .imageset, or .colorset is an asset declaration, not an arbitrary file directory. Its Contents.json tells Xcode which source image belongs to which named asset and appearance.

No tracked Swift source directly requests IntroGraphics, IntroGraphicsBlack, or IntroGraphicsLandscape by Image(name) at the time of this audit. They remain source assets and should not be removed merely because no current direct call was found.

### Catalog Metadata and Accent Color

| Exact source file | Role / format | Why it is not edited in a built product |
| --- | --- | --- |
| Weather/Resources/Assets.xcassets/Contents.json | Root Xcode asset-catalog metadata JSON. | The compiled asset catalog is generated; update this source manifest through Xcode if needed. |
| Weather/Resources/Assets.xcassets/AccentColor.colorset/Contents.json | Manifest for the universal named AccentColor color asset. The current manifest has no explicit light/dark component values. | This JSON is the source declaration; do not fabricate or edit a compiled color resource. |

### App Icon Source Files

All three icon PNGs are 1024x1024 RGB source art. The manifest, not the filename alone, assigns their iOS appearance slots.

| Exact source file | Role / format | Ownership and edit rule |
| --- | --- | --- |
| Weather/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json | JSON manifest for default, dark-luminosity, and tinted-luminosity universal iOS app-icon slots. | Xcode asset-catalog source. Keep filenames synchronized with this manifest. |
| Weather/Resources/Assets.xcassets/AppIcon.appiconset/icon-iOS-Default-1024x1024@1x.png | Default universal iOS icon PNG. | Main app visual source art; replace only in the source catalog. |
| Weather/Resources/Assets.xcassets/AppIcon.appiconset/icon-iOS-Dark-1024x1024@1x.png | Dark-luminosity universal iOS icon PNG. | Main app visual source art; replace only in the source catalog. |
| Weather/Resources/Assets.xcassets/AppIcon.appiconset/icon-iOS-Dark-1024x1024@1x 1.png | Tinted-luminosity universal iOS icon PNG. The space and trailing 1 are part of the real filename. | Main app visual source art; if renamed, update the manifest in the same change. |

### Intro Image Source Files

All five PNGs below are 1179x2556 RGB source images. Each associated JSON manifest determines the named asset and appearance mapping.

| Exact source file | Role / format | Ownership and edit rule |
| --- | --- | --- |
| Weather/Resources/Assets.xcassets/IntroGraphics.imageset/Contents.json | JSON manifest for the named IntroGraphics image asset with light/dark luminosity variants. | Xcode asset-catalog source. Keep image filenames in sync with this manifest. |
| Weather/Resources/Assets.xcassets/IntroGraphics.imageset/IntroGraphics_Light.png | Light-appearance source PNG for IntroGraphics. | App visual source art; do not edit a compiled asset copy. |
| Weather/Resources/Assets.xcassets/IntroGraphics.imageset/IntroGraphics_Dark.png.png | Dark-appearance source PNG for IntroGraphics. The doubled .png.png is the real manifest-referenced filename. | App visual source art; rename only with its manifest update. |
| Weather/Resources/Assets.xcassets/IntroGraphicsBlack.imageset/Contents.json | JSON manifest for the single universal IntroGraphicsBlack asset. | Xcode asset-catalog source. |
| Weather/Resources/Assets.xcassets/IntroGraphicsBlack.imageset/IntroGraphicsBlack.png | Universal source PNG for IntroGraphicsBlack. | App visual source art; compiled output is regenerated. |
| Weather/Resources/Assets.xcassets/IntroGraphicsLandscape.imageset/Contents.json | JSON manifest for named IntroGraphicsLandscape light/dark variants. | Xcode asset-catalog source. |
| Weather/Resources/Assets.xcassets/IntroGraphicsLandscape.imageset/IntroGraphicsLandscape_Light.png | Light-appearance source PNG for IntroGraphicsLandscape. | App visual source art; compiled output is regenerated. |
| Weather/Resources/Assets.xcassets/IntroGraphicsLandscape.imageset/IntroGraphicsLandscape_Dark.png | Dark-appearance source PNG for IntroGraphicsLandscape. | App visual source art; compiled output is regenerated. |

Asset-catalog editing rule:
- Modify source PNGs and matching Contents.json files in the repository, preferably using Xcode's asset-catalog editor.
- Do not edit Assets.car or files inside a built .app/.appex.
- If a source PNG filename changes, update the relevant manifest in the same change.

## String Catalog Sources

An .xcstrings file is an Xcode JSON-backed String Catalog. The three audited catalogs use source language en and format version 1.1. They are source records, not generated translation exports.

Supported catalog locales are:
de, en, es, fr, it, ja, ko, pt, ru, zh-Hans, and zh-Hant.

| Exact source file | Owner and role | Audited coverage | Why it is not edited inline in a built product |
| --- | --- | --- | --- |
| Weather/Localizable.xcstrings | Main Weather Atlas app catalog for UI, formatting templates, messages, and app-level feature copy. | 350 source entries; 333 translated entries in each supported locale; 3,681 translated units total. | The catalog is compiled into the app; edit the source catalog, preferably in Xcode. |
| Weather/Widgets/Localizable.xcstrings | WeatherWidgets extension catalog for widget configuration and presentation copy. | 17 source entries; all 17 translated in every supported locale; 187 translated units total. | The extension bundle contains generated localization output; edit this catalog source. |
| Weather/Widgets/WeatherWidgets-InfoPlist.xcstrings | WeatherWidgets extension Info.plist string catalog. | Two keys, CFBundleDisplayName and CFBundleName, translated in all eleven supported locales; 22 translated units total. | The extension bundle copy is generated from this source catalog. |

String-catalog editing rule:
- The main app owns Weather/Localizable.xcstrings.
- The widget extension owns the two Weather/Widgets/*.xcstrings files.
- Widget runtime code can receive a small set of already-localized strings from the shared App Group. That runtime hand-off is separate from these source catalogs and does not make widgets writers of main-app catalog data.
- Prefer Xcode's String Catalog editor. If raw JSON must be changed, preserve catalog structure, source keys, locale IDs, placeholders, and translation states.
- Do not translate formatting tokens such as %@, %lld, or %% as ordinary prose; code interprets them.

## Main-App Info.plist Localizations

Weather/*.lproj/InfoPlist.strings uses the classic localized .strings format. iOS reads these values before SwiftUI launches for the displayed app name and the system location-permission prompt.

Every listed file contains these three Apple bundle keys:
- CFBundleDisplayName: displayed app name.
- CFBundleName: bundle name.
- NSLocationWhenInUseUsageDescription: system current-location permission explanation.

| Locale | Exact source file | Owner / role | Why it is not edited in a build product |
| --- | --- | --- | --- |
| Base | Weather/Base.lproj/InfoPlist.strings | Main-app English fallback. | Built app copy is regenerated from this tracked source. |
| de | Weather/de.lproj/InfoPlist.strings | German main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| en | Weather/en.lproj/InfoPlist.strings | English main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| es | Weather/es.lproj/InfoPlist.strings | Spanish main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| fr | Weather/fr.lproj/InfoPlist.strings | French main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| it | Weather/it.lproj/InfoPlist.strings | Italian main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| ja | Weather/ja.lproj/InfoPlist.strings | Japanese main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| ko | Weather/ko.lproj/InfoPlist.strings | Korean main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| pt | Weather/pt.lproj/InfoPlist.strings | Portuguese main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| ru | Weather/ru.lproj/InfoPlist.strings | Russian main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| zh-Hans | Weather/zh-Hans.lproj/InfoPlist.strings | Simplified-Chinese main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |
| zh-Hant | Weather/zh-Hant.lproj/InfoPlist.strings | Traditional-Chinese main-app app-name and permission-prompt copy. | Built app copy is regenerated from this tracked source. |

Info.plist localization editing rule:
- These are main-app resources. The widget extension's bundle-name localization belongs in Weather/Widgets/WeatherWidgets-InfoPlist.xcstrings instead.
- Preserve the exact Apple key names, valid .strings quoting, semicolons, comments, and UTF-8 encoding.
- Do not move the permission explanation solely into a SwiftUI String Catalog. iOS needs this Info.plist localization before the app's normal UI exists.

## Complete Coverage Checklist

This guide explicitly covers all 31 requested tracked non-commentable resource files:

| Family | Count | Exact coverage |
| --- | ---: | --- |
| City CSV files | 2 | Weather/Resources/Cities/worldcities.csv; Weather/Resources/Cities/country_city_coordinates.csv |
| Asset catalog files | 14 | Six JSON manifests: root, AccentColor, AppIcon, IntroGraphics, IntroGraphicsBlack, and IntroGraphicsLandscape; plus eight PNGs: three app icons and five intro images. |
| String Catalog files | 3 | Weather/Localizable.xcstrings; Weather/Widgets/Localizable.xcstrings; Weather/Widgets/WeatherWidgets-InfoPlist.xcstrings |
| Main-app Info.plist strings files | 12 | Base, de, en, es, fr, it, ja, ko, pt, ru, zh-Hans, and zh-Hant InfoPlist.strings |

For a source-reading session, read the resources in this order:
1. The two CSV schemas, to understand where place search, population selection, and timezone data originate.
2. Weather/Localizable.xcstrings, to see the main app's user-facing language.
3. The two widget catalogs, to see copy owned specifically by the extension.
4. The twelve InfoPlist.strings files, to see text iOS displays before SwiftUI begins.
5. The asset catalog manifests and PNGs, to see visual source art and light/dark/tinted associations.
