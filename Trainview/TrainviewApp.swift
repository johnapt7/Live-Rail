//
//  TrainviewApp.swift
//  Trainview
//
//  Created by John Thompson on 26/04/2026.
//

import SwiftUI
import UserNotifications

/// Opts the app into showing notifications while it is in the foreground.
/// Without a delegate implementing `willPresent`, iOS silently discards
/// banners posted while the app is on screen — which is exactly when the
/// tracker's poll loop posts them.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Posted when the user taps a tracked-journey notification; ContentView
    /// routes to the tracked journey.
    static let journeyTapNotification = Notification.Name("journeyNotificationTapped")
    /// Posted when the user taps a station-arrival habit suggestion;
    /// ContentView opens that station's board filtered to the habit.
    static let habitTapNotification = Notification.Name("habitNotificationTapped")

    struct HabitOpen {
        let station: Station
        let destination: Station
    }

    /// Set when a tap arrives before ContentView has subscribed (cold start —
    /// the tap itself launched the app). ContentView consumes it in onAppear.
    private(set) var pendingJourneyOpen = false
    private(set) var pendingHabitOpen: HabitOpen?

    func consumePendingJourneyOpen() -> Bool {
        let pending = pendingJourneyOpen
        pendingJourneyOpen = false
        return pending
    }

    func consumePendingHabitOpen() -> HabitOpen? {
        let pending = pendingHabitOpen
        pendingHabitOpen = nil
        return pending
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let userInfo = response.notification.request.content.userInfo
        if let stationCode = userInfo["habitStation"] as? String,
           let destinationCode = userInfo["habitDest"] as? String {
            let open = HabitOpen(
                station: Station(code: stationCode, name: userInfo["habitStationName"] as? String ?? stationCode),
                destination: Station(code: destinationCode, name: userInfo["habitDestName"] as? String ?? destinationCode)
            )
            await MainActor.run {
                pendingHabitOpen = open
                NotificationCenter.default.post(name: Self.habitTapNotification, object: nil)
            }
            return
        }
        await MainActor.run {
            pendingJourneyOpen = true
            NotificationCenter.default.post(name: Self.journeyTapNotification, object: nil)
        }
    }
}

@main
struct TrainviewApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        // Must exist from process start: iOS relaunches the app in the
        // background when a habit-station geofence fires, and only a
        // delegate registered during launch receives that event.
        StationArrivalWatcher.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
