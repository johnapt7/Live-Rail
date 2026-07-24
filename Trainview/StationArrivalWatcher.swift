import CoreLocation
import UserNotifications
import UIKit

/// Watches geofences around stations with a qualifying journey habit. When
/// the user walks into one, iOS relaunches the app in the background and
/// this fires a notification with the next departure of their usual journey
/// — platform included — before they've touched the phone.
final class StationArrivalWatcher: NSObject, CLLocationManagerDelegate {
    static let shared = StationArrivalWatcher()

    private static let regionPrefix = "habit-"
    private static let regionRadiusMetres: CLLocationDistance = 500
    /// Lingering near a station (or exit/re-entry on its edge) must not
    /// re-fire; one suggestion per station per window.
    private static let cooldown: TimeInterval = 90 * 60
    private static let firedKeyPrefix = "habitFired."

    private let manager = CLLocationManager()
    private let habits = JourneyHabitsStore.shared

    override init() {
        super.init()
        manager.delegate = self
        habits.onHabitsChanged = { [weak self] in self?.syncRegions() }
    }

    /// Called at every launch — including background relaunches on region
    /// entry, where init alone re-establishes the delegate that receives
    /// the pending region event.
    func start() {
        syncRegions()
    }

    private func syncRegions() {
        let qualifying = habits.qualifyingHabits()
        guard !qualifying.isEmpty else {
            for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
                manager.stopMonitoring(for: region)
            }
            return
        }
        // Region monitoring needs Always; the first qualifying habit is the
        // moment the feature earns asking for the upgrade.
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }

        let wanted = Set(qualifying.map { Self.regionPrefix + $0.stationCode })
        for region in manager.monitoredRegions
        where region.identifier.hasPrefix(Self.regionPrefix) && !wanted.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        let monitored = Set(manager.monitoredRegions.map(\.identifier))
        for habit in qualifying where !monitored.contains(Self.regionPrefix + habit.stationCode) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: habit.latitude, longitude: habit.longitude),
                radius: Self.regionRadiusMetres,
                identifier: Self.regionPrefix + habit.stationCode
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Self.regionPrefix) else { return }
        let stationCode = String(region.identifier.dropFirst(Self.regionPrefix.count))
        Task { @MainActor in
            StationArrivalWatcher.shared.suggestJourney(at: stationCode)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            StationArrivalWatcher.shared.syncRegions()
        }
    }

    // MARK: - Suggestion

    @MainActor
    private func suggestJourney(at stationCode: String) {
        // Mid-journey the tracker owns the lock screen — a "your usual
        // train" banner while riding INTO this station would be noise.
        guard UserDefaults.standard.data(forKey: "trackingSnapshot") == nil else { return }
        guard let habit = habits.habit(for: stationCode) else { return }

        let firedKey = Self.firedKeyPrefix + stationCode
        let lastFired = UserDefaults.standard.double(forKey: firedKey)
        guard Date().timeIntervalSince1970 - lastFired > Self.cooldown else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: firedKey)

        // Background relaunches get seconds, not minutes — wrap the fetch in
        // a background task so the notification reliably goes out.
        let backgroundTask = UIApplication.shared.beginBackgroundTask()
        Task {
            defer { UIApplication.shared.endBackgroundTask(backgroundTask) }
            guard let board = try? await APIClient.shared.getBoard(
                crs: habit.stationCode, type: "departures", rows: 10, filterCrs: habit.destinationCode
            ) else { return }
            guard let service = board.services.first(where: { !$0.isCancelled }) ?? board.services.first else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your usual train to \(habit.destinationName)"
            content.body = Self.suggestionBody(for: service)
            content.sound = .default
            content.threadIdentifier = "habit-\(habit.stationCode)"
            // The user is physically walking into the station right now.
            content.interruptionLevel = .timeSensitive
            content.userInfo = [
                "habitStation": habit.stationCode,
                "habitStationName": habit.stationName,
                "habitDest": habit.destinationCode,
                "habitDestName": habit.destinationName,
            ]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "habit-\(habit.stationCode)-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            ))
        }
    }

    /// Mirrors board semantics via Train(from:) — confirmed platforms plain,
    /// learned predictions hedged with "(predicted)".
    static func suggestionBody(for service: BoardService) -> String {
        if service.isCancelled {
            return "The \(service.scheduledTime) is cancelled — open Trainview for alternatives"
        }
        var body = "Next train \(service.scheduledTime)"
        if isClockTime(service.expectedTime), service.expectedTime != service.scheduledTime {
            body += " · expected \(service.expectedTime)"
        } else if service.expectedTime == "Delayed" {
            body += " · delayed"
        }
        let train = Train(from: service)
        if train.platform != "—" && !train.platform.isEmpty {
            body += " · Platform \(train.platform)"
            if train.isPredictedPlatform {
                body += " (predicted)"
            }
        }
        return body
    }

    private static func isClockTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        return parts.count == 2 && Int(parts[0]) != nil && Int(parts[1]) != nil
    }
}
