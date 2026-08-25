//
//  ErrorAlerts.swift
//  Weather
//
//  Purpose: Defines developer diagnostics and localized weather-data issue
//  messages. It is the translation boundary between precise model failures and
//  short, person-readable copy for native alerts.
//

import Foundation
import Observation
import OSLog
import SwiftUI

// MARK: - Native Missing-Data Alerts

/// One native alert describing data that could not be rendered honestly.
///
/// `key` identifies the active failure episode independently from `id`, which
/// is presentation identity. Callers resolve the key after the data becomes
/// available again, allowing a later failure to alert once more.
struct MissingDataAlert: Identifiable, Equatable {
    let id = UUID()
    let key: String
    let title: String
    let message: String
}

/// An immutable description of one missing-data episode reported by a SwiftUI
/// surface. The stable key is deliberately separate from the alert's `id` so
/// the recovery layer can retry each episode once before it becomes eligible
/// for presentation.
struct MissingDataAlertReport: Hashable {
    let key: String
    let title: String
    let message: String
}

/// The caller-owned recovery work for a missing-data episode.
///
/// This stays on the main actor because callers typically refresh an
/// observable store. It is supplied by the view and retained only for an
/// active recovery task; no action closure is put into SwiftUI's environment.
typealias MissingDataRetry = @MainActor () async -> Void

/// One shared one-shot re-fetch. Several cards can join the same recovery
/// context (for example daily, ten-day, and metric cards for one city) without
/// each forcing a competing WeatherKit request. Its task captures the supplied
/// retry only while the recovery context has participating missing reports.
private struct MissingDataRecovery {
    let id = UUID()
    let task: Task<Void, Never>
    var reportKeys: Set<String>
}

/// App-wide queue for blank-first, native missing-data presentation.
///
/// Models and views report stable failure keys; the center deduplicates one
/// active episode, queues unrelated failures, and yields before presenting so
/// SwiftUI can paint the corresponding blank value or chart first.
@MainActor
@Observable
final class MissingDataAlertCenter {
    // MARK: - Queue and Recovery State

    private(set) var currentAlert: MissingDataAlert?

    @ObservationIgnored private var queuedAlerts: [MissingDataAlert] = []
    @ObservationIgnored private var activeKeys: Set<String> = []
    /// The recovery context associated with each currently missing report.
    /// Keeping this independently from alert presentation lets several reports
    /// share a retry without sharing — or suppressing — their own final alert.
    @ObservationIgnored private var recoveryKeyByReportKey: [String: String] = [:]
    /// The recovery remains registered after it completes until all linked
    /// reports resolve. A card that appears slightly later therefore joins the
    /// completed retry instead of creating a second request for the same data.
    @ObservationIgnored private var recoveries: [String: MissingDataRecovery] = [:]

    // MARK: - Reporting Lifecycle

    /// Queues an already-confirmed failure episode.
    ///
    /// Weather and place-data paths should normally use
    /// `retryThenReport(_:recoveryKey:retry:isStillMissing:)` or the
    /// `.reportingMissingData(_:recoveryKey:retrying:)` view modifier instead. This
    /// remains available for non-refetchable failures and existing call sites
    /// during migration.
    func report(key: String, title: String, message: String) {
        // Do not let a legacy reporter bypass the retry currently owning this
        // report. The retry path calls `enqueue(_:)` directly once it ends.
        guard recoveryKeyByReportKey[key] == nil else { return }
        enqueue(MissingDataAlert(key: key, title: title, message: message))
    }

    /// Performs exactly one caller-supplied re-fetch before queuing an alert.
    ///
    /// Supply the same `recoveryKey` to every surface whose data comes from
    /// the same refreshable source. Those surfaces wait for one shared retry,
    /// then each independently decides whether its own report still warrants
    /// an alert.
    ///
    /// `isStillMissing` is evaluated after the retry returns. It keeps the
    /// policy usable by non-view callers, whose underlying observable source
    /// may have been repaired while the retry was running. The closure is
    /// never placed in SwiftUI's environment.
    func retryThenReport(
        _ report: MissingDataAlertReport,
        recoveryKey: String,
        retry: @escaping MissingDataRetry,
        isStillMissing: @MainActor () -> Bool
    ) async {
        // An already-alerted episode remains armed only for de-duplication;
        // it must not trigger a second retry while its view is still visible.
        guard !activeKeys.contains(report.key) else { return }

        let normalizedRecoveryKey = normalizedRecoveryKey(
            recoveryKey,
            fallback: report.key
        )
        let recovery = joinRecovery(
            for: normalizedRecoveryKey,
            reportKey: report.key,
            retry: retry
        )

        await recovery.task.value
        // Give Observation one turn to publish a successful refresh before
        // reading the current failure state.
        await Task.yield()

        guard !Task.isCancelled,
              recoveries[normalizedRecoveryKey]?.id == recovery.id,
              recoveries[normalizedRecoveryKey]?.reportKeys.contains(report.key) == true,
              isStillMissing() else {
            return
        }

        enqueue(
            MissingDataAlert(
                key: report.key,
                title: report.title,
                message: report.message
            )
        )
    }

    /// Marks data available again and re-arms that key for a future failure.
    func resolve(key: String) {
        detachReportKeyFromRecovery(key)
        activeKeys.remove(key)
        queuedAlerts.removeAll { $0.key == key }
        guard currentAlert?.key == key else { return }
        currentAlert = nil
        presentNextAfterYield()
    }

    /// Dismisses the current native alert without pretending its data recovered.
    /// The key remains active, preventing an alert loop on every view redraw.
    func dismissCurrent() {
        currentAlert = nil
        presentNextAfterYield()
    }

    /// Clears presentation and deduplication state during a full app reset.
    func reset() {
        currentAlert = nil
        queuedAlerts = []
        activeKeys = []
        recoveries.values.forEach { $0.task.cancel() }
        recoveries = [:]
        recoveryKeyByReportKey = [:]
    }

    // MARK: - Shared Retry Coordination

    /// Returns the existing recovery for this context or starts its one and
    /// only retry. Every participating report waits on the same task.
    private func joinRecovery(
        for recoveryKey: String,
        reportKey: String,
        retry: @escaping MissingDataRetry
    ) -> MissingDataRecovery {
        if let oldRecoveryKey = recoveryKeyByReportKey[reportKey],
           oldRecoveryKey != recoveryKey {
            detachReportKeyFromRecovery(reportKey)
        }
        recoveryKeyByReportKey[reportKey] = recoveryKey

        if var recovery = recoveries[recoveryKey] {
            recovery.reportKeys.insert(reportKey)
            recoveries[recoveryKey] = recovery
            return recovery
        }

        let task = Task { @MainActor in
            await retry()
        }
        let recovery = MissingDataRecovery(
            task: task,
            reportKeys: [reportKey]
        )
        recoveries[recoveryKey] = recovery
        return recovery
    }

    /// Removes one report from its shared recovery. The underlying retry is
    /// cancelled only when no visible missing-data surface still needs it.
    private func detachReportKeyFromRecovery(_ reportKey: String) {
        guard let recoveryKey = recoveryKeyByReportKey.removeValue(forKey: reportKey),
              var recovery = recoveries[recoveryKey] else {
            return
        }

        recovery.reportKeys.remove(reportKey)
        guard recovery.reportKeys.isEmpty else {
            recoveries[recoveryKey] = recovery
            return
        }

        recovery.task.cancel()
        recoveries.removeValue(forKey: recoveryKey)
    }

    // MARK: - Alert Queue Internals

    private func normalizedRecoveryKey(_ key: String, fallback: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Adds a confirmed failure to the alert queue after a blank state has had
    /// one scheduling turn to render.
    private func enqueue(_ alert: MissingDataAlert) {
        guard activeKeys.insert(alert.key).inserted else { return }

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, activeKeys.contains(alert.key) else { return }
            if currentAlert == nil {
                currentAlert = alert
            } else {
                queuedAlerts.append(alert)
            }
        }
    }

    private func presentNextAfterYield() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, currentAlert == nil else { return }
            while let next = queuedAlerts.first {
                queuedAlerts.removeFirst()
                guard activeKeys.contains(next.key) else { continue }
                currentAlert = next
                return
            }
        }
    }
}

// MARK: - SwiftUI Missing-Data Recovery

private struct MissingDataAlertReportingModifier: ViewModifier {
    let report: MissingDataAlertReport?
    let recoveryKey: String?
    let retry: MissingDataRetry?

    @Environment(MissingDataAlertCenter.self) private var alertCenter
    @State private var reportedKey: String?

    func body(content: Content) -> some View {
        content
            // The stable issue key, rather than changing alert copy, defines
            // one recovery episode. If the report resolves, SwiftUI cancels
            // this task before it is allowed to queue its alert.
            .task(id: report) {
                await synchronizeReport(for: report)
            }
            .onDisappear {
                guard let reportedKey else { return }
                alertCenter.resolve(key: reportedKey)
                self.reportedKey = nil
            }
    }

    @MainActor
    private func synchronizeReport(for currentReport: MissingDataAlertReport?) async {
        if let reportedKey, reportedKey != currentReport?.key {
            alertCenter.resolve(key: reportedKey)
            self.reportedKey = nil
        }

        guard let currentReport else { return }
        reportedKey = currentReport.key

        guard let retry else {
            // Compatibility path for call sites that have not yet supplied a
            // refetch action. New weather-data paths should use `retrying:`.
            alertCenter.report(
                key: currentReport.key,
                title: currentReport.title,
                message: currentReport.message
            )
            return
        }

        await alertCenter.retryThenReport(
            currentReport,
            recoveryKey: recoveryKey ?? currentReport.key,
            retry: retry,
            isStillMissing: {
                // `.task(id: report)` cancels when the source clears the
                // report. Checking the owned episode here also prevents a
                // stale task from presenting after replacement or dismissal.
                !Task.isCancelled && reportedKey == currentReport.key
            }
        )
    }
}

extension View {
    /// Draws the blank state first, then queues a native alert. Prefer the
    /// `retrying:` overload for weather or place data so one immediate
    /// re-fetch happens before any alert can appear.
    func reportingMissingData(_ report: MissingDataAlertReport?) -> some View {
        modifier(
            MissingDataAlertReportingModifier(
                report: report,
                recoveryKey: nil,
                retry: nil
            )
        )
    }

    /// Draws the blank state, runs one immediate async re-fetch, and shows an
    /// alert only if the same report remains active afterwards. Use the same
    /// `recoveryKey` for cards backed by the same refreshable source; they
    /// wait for one shared retry. The closure belongs to this modifier rather
    /// than the app environment.
    func reportingMissingData(
        _ report: MissingDataAlertReport?,
        recoveryKey: String,
        retrying retry: @escaping MissingDataRetry
    ) -> some View {
        modifier(
            MissingDataAlertReportingModifier(
                report: report,
                recoveryKey: recoveryKey,
                retry: retry
            )
        )
    }
}

// MARK: - Developer Diagnostics

/// Debug-only reporting for internal catalog and geocoder invariants.
///
/// This uses the system log only in DEBUG builds. It keeps a burst of
/// diagnostics from blocking app work when a console is slow to consume output.
enum DeveloperDiagnostics {
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Yutao-Wu.Weather",
        category: "DeveloperDiagnostics"
    )
#endif

    /// Logs implementation diagnostics without exposing them as user alerts.
    static func show(title: String, message: String) {
        #if DEBUG
        logger.error("\(title, privacy: .public): \(message, privacy: .public)")
        #endif
    }
}

// MARK: - Localized Issue Messages

/// Builds localized, city-specific native-alert copy for an exact data issue.
///
/// `WeatherDataIssue` remains structured inside the model layer. This `switch`
/// is the one place that chooses the wording, which keeps views from needing
/// to understand every missing-data case.
func weatherDataIssueMessage(
    _ issue: WeatherDataIssue,
    cityName: String,
    locale: Locale
) -> String {
    let trimmedName = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    let placeName = trimmedName.isEmpty
        ? localizedString("this location", locale: locale)
        : trimmedName

    switch issue.kind {
    case .weatherRequestFailed:
        return String(
            format: localizedString(
                "Weather data is missing for %@ because the request failed.",
                locale: locale
            ),
            locale: locale,
            placeName
        )
    case .unresolvedPlace:
        return String(
            format: localizedString("Place data is missing for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingSunriseOrSunset:
        return String(
            format: localizedString("Missing sunrise or sunset data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingSunriseData:
        return String(
            format: localizedString("Missing sunrise data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingSunsetData:
        return String(
            format: localizedString("Missing sunset data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingHourlyData:
        return String(
            format: localizedString("Missing hourly data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingForecastData:
        return String(
            format: localizedString("Missing forecast data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingConditionData:
        return String(
            format: localizedString("Missing weather condition data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingTemperatureData:
        return String(
            format: localizedString("Missing temperature data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingApparentTemperatureData:
        return String(
            format: localizedString("Missing feels-like temperature data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingCloudCoverData:
        return String(
            format: localizedString("Missing cloud-cover data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingPrecipitationChanceData:
        return String(
            format: localizedString("Missing precipitation-chance data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingVisibilityData:
        return String(
            format: localizedString("Missing visibility data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .missingUVIndexData:
        return String(
            format: localizedString("Missing UV-index data for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .invalidWeatherValue:
        return String(
            format: localizedString(
                "Invalid weather data for %@ has been left blank.",
                locale: locale
            ),
            locale: locale,
            placeName
        )
    case .missingTimeZone:
        return String(
            format: localizedString("Missing time zone for %@.", locale: locale),
            locale: locale,
            placeName
        )
    case .unknownWeatherSymbol:
        // A source symbol is useful in a debug-quality warning, but only after
        // trimming whitespace so a malformed empty value gets the clearer
        // generic message below.
        let symbol = issue.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let symbol, !symbol.isEmpty {
            return String(
                format: localizedString("Unknown weather symbol \"%@\" for %@.", locale: locale),
                locale: locale,
                symbol,
                placeName
            )
        }
        return String(
            format: localizedString("Missing weather symbol for %@.", locale: locale),
            locale: locale,
            placeName
        )
    }
}
