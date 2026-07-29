import UserNotifications

final class TrainNotificationManager {

    struct Snapshot {
        let platform: String?
        let isPredictedPlatform: Bool
        let expectedDeparture: String?
        let isCancelled: Bool
    }

    private var lastSnapshot: Snapshot?
    private var trainDescription = ""
    private var serviceId = ""
    private var isAuthorized = false
    private var didNotifyStopIsNext = false
    private var scheduledReminderKey: String?

    func configure(train: Train, boardingStation: Station) {
        serviceId = train.serviceId
        trainDescription = "Your \(train.time) to \(train.destination)"
        lastSnapshot = nil
        didNotifyStopIsNext = false
        scheduledReminderKey = nil
    }

    /// Fired once per tracked journey, when the user's alighting stop becomes
    /// the next stop.
    func notifyStopIsNext(_ stationName: String) {
        guard isAuthorized, !didNotifyStopIsNext else { return }
        didNotifyStopIsNext = true
        scheduleNotification(
            id: "\(serviceId)-stop-next",
            title: "Your stop is next",
            body: "Get ready to get off at \(stationName)"
        )
    }

    /// Connection prompts for a two-leg journey: the heads-up as the change
    /// station becomes next, and the call to action on arrival there.
    /// Returns whether the alert was actually scheduled, so the tracker only
    /// consumes its one-shot on success.
    @discardableResult
    func notifyConnection(_ connection: PendingConnection, arrived: Bool) -> Bool {
        guard isAuthorized else { return false }
        var body = "Your \(connection.departTime) to \(connection.towards) leaves"
        if let platform = connection.platform, !platform.isEmpty, platform != "—" {
            body += " from Platform \(platform)"
        }
        body += " — open to switch tracking in one tap."
        scheduleNotification(
            id: "\(serviceId)-connection-\(arrived ? "arrived" : "next")",
            title: arrived
                ? "Time to change at \(connection.changeName)"
                : "\(connection.changeName) is next — change there",
            body: body
        )
        return true
    }

    /// Fired once when delays shrink the change wait below the minimum sane
    /// change time (or past the connection's departure entirely).
    @discardableResult
    func notifyConnectionAtRisk(_ connection: PendingConnection, waitMinutes: Int) -> Bool {
        guard isAuthorized else { return false }
        let body = waitMinutes < 0
            ? "Your \(connection.departTime) to \(connection.towards) looks missed — check the next service from \(connection.changeName)."
            : "Delays leave only \(waitMinutes) min at \(connection.changeName) for the \(connection.departTime) to \(connection.towards)."
        scheduleNotification(
            id: "\(serviceId)-connection-risk",
            title: "Connection at risk",
            body: body
        )
        return true
    }

    /// Journey-complete confirmation: tells the user the destination was
    /// reached and live tracking has ended. Fired by the tracker exactly once
    /// per journey, from completeJourney.
    func notifyArrived(at stationName: String) {
        guard isAuthorized else { return }
        scheduleNotification(
            id: "\(serviceId)-arrived",
            title: "Journey complete",
            body: "Arrived at \(stationName) — live tracking has ended."
        )
    }

    /// Pre-departure reminder, pended with the system so it fires even if the
    /// app is suspended by then. Re-scheduled whenever the expected departure
    /// or platform changes; the key guard avoids churning identical requests.
    func scheduleDepartureReminder(departure: Date, platform: String?) {
        guard isAuthorized else { return }

        let untilDeparture = departure.timeIntervalSinceNow
        // Departure already passed (or is seconds away): nothing useful to say.
        guard untilDeparture > 45 else { return }

        let key = "\(Int(departure.timeIntervalSince1970))-\(platform ?? "?")"
        guard key != scheduledReminderKey else { return }
        scheduledReminderKey = key

        let fireInterval = departure.addingTimeInterval(-5 * 60).timeIntervalSinceNow
        let minutesLeft = max(1, Int((untilDeparture / 60).rounded()))
        // Tracking started inside the 5-minute window: alert now with the
        // real minutes remaining instead of silently skipping the reminder.
        let immediate = fireInterval <= 10

        var body = immediate
            ? "\(trainDescription) leaves in \(minutesLeft) minute\(minutesLeft == 1 ? "" : "s")"
            : "\(trainDescription) leaves in 5 minutes"
        if let platform, !platform.isEmpty {
            body += " from Platform \(platform)"
        }

        let content = UNMutableNotificationContent()
        content.title = "Departing soon"
        content.body = body
        content.sound = .default
        content.threadIdentifier = serviceId
        // Five minutes to boarding is exactly what time-sensitive is for.
        content.interruptionLevel = .timeSensitive

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["\(serviceId)-departing-soon"])
        center.add(UNNotificationRequest(
            identifier: "\(serviceId)-departing-soon",
            content: content,
            trigger: immediate ? nil : UNTimeIntervalNotificationTrigger(timeInterval: fireInterval, repeats: false)
        )) { [weak self] error in
            guard let error else { return }
            print("Notification scheduling failed (departing-soon): \(error)")
            // Clear the key so the next poll retries instead of assuming success.
            DispatchQueue.main.async { self?.scheduledReminderKey = nil }
        }
    }

    /// Fired once when the boarding station's departure is confirmed. Also
    /// clears any still-pending "departing soon" reminder — it's now stale.
    /// Returns whether the alert was actually scheduled.
    @discardableResult
    func notifyDeparted(from stationName: String) -> Bool {
        guard isAuthorized else { return false }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["\(serviceId)-departing-soon"])
        scheduleNotification(
            id: "\(serviceId)-departed",
            title: "On the move",
            body: "\(trainDescription) has departed \(stationName)"
        )
        return true
    }

    /// Fired as the journey advances past each calling point. The alighting
    /// stop is excluded — it gets the dedicated "Your stop is next" alert.
    /// Returns whether the alert was actually scheduled, so callers only
    /// consume their one-shot state on success.
    @discardableResult
    func notifyNextStop(_ stationName: String, expectedTime: String?, stopsToGo: Int) -> Bool {
        guard isAuthorized else { return false }
        var body = "Next stop \(stationName)"
        if let expectedTime, isClockTime(expectedTime) {
            body += " · \(expectedTime)"
        }
        if stopsToGo == 1 {
            body += " — 1 stop before yours"
        } else if stopsToGo > 1 {
            body += " — \(stopsToGo) stops before yours"
        }
        // Only sent when no Live Activity is showing; routine progress
        // never needs to pierce Focus.
        scheduleNotification(
            id: "\(serviceId)-next-\(stationName)",
            title: "Next stop",
            body: body,
            interruption: .active
        )
        return true
    }

    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            // Provisional/ephemeral grants can deliver quietly — better than
            // silently dropping everything.
            isAuthorized = [.authorized, .provisional, .ephemeral]
                .contains(settings.authorizationStatus)
        }
    }

    /// Re-reads the system's answer without ever prompting. Called on session
    /// resume and foreground return — the cached flag otherwise goes stale
    /// (always-false after a relaunch, or wrong after a Settings change).
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = [.authorized, .provisional, .ephemeral]
            .contains(settings.authorizationStatus)
    }

    func evaluateChanges(
        platform: String?,
        isPredictedPlatform: Bool,
        expectedDeparture: String?,
        scheduledDeparture: String?,
        isCancelled: Bool,
        hasDepartedBoardingStation: Bool
    ) {
        guard isAuthorized, !hasDepartedBoardingStation else { return }

        let currentPlatform = normalizedPlatform(platform)
        let currentExpected = expectedDeparture

        defer {
            lastSnapshot = Snapshot(
                platform: currentPlatform,
                isPredictedPlatform: isPredictedPlatform,
                expectedDeparture: currentExpected,
                isCancelled: isCancelled
            )
        }

        guard let previous = lastSnapshot else { return }

        if isCancelled && !previous.isCancelled {
            scheduleNotification(
                id: "\(serviceId)-cancelled",
                title: "Train Cancelled",
                body: "\(trainDescription) has been cancelled. Open Trainview for alternatives."
            )
            return
        }

        if let newPlat = currentPlatform {
            if let oldPlat = previous.platform, newPlat != oldPlat {
                scheduleNotification(
                    id: "\(serviceId)-platform-\(newPlat)",
                    title: "Platform Change",
                    body: "\(trainDescription) has moved to Platform \(newPlat)"
                )
            } else if !isPredictedPlatform && previous.isPredictedPlatform {
                scheduleNotification(
                    id: "\(serviceId)-platform-confirmed",
                    title: "Platform Confirmed",
                    body: "\(trainDescription) is confirmed for Platform \(newPlat)"
                )
            }
        }

        if let newExp = currentExpected,
           let scheduled = scheduledDeparture,
           newExp != previous.expectedDeparture,
           isClockTime(newExp),
           newExp != scheduled {
            // Informative rather than actionable — no need to pierce Focus.
            scheduleNotification(
                id: "\(serviceId)-delay-\(newExp)",
                title: "Delay Update",
                body: "\(trainDescription) is now expected at \(newExp)",
                interruption: .active
            )
        }
    }

    /// Advances the comparison baseline without emitting — used while the
    /// backend authors these alerts over APNs, so a mid-journey fallback to
    /// local alerting resumes from the present instead of replaying history.
    func recordSnapshot(
        platform: String?,
        isPredictedPlatform: Bool,
        expectedDeparture: String?,
        isCancelled: Bool
    ) {
        lastSnapshot = Snapshot(
            platform: normalizedPlatform(platform),
            isPredictedPlatform: isPredictedPlatform,
            expectedDeparture: expectedDeparture,
            isCancelled: isCancelled
        )
    }

    /// Drops the comparison baseline after the app wakes from suspension —
    /// the next evaluation records state without emitting, so changes that
    /// accumulated while suspended never replay as a burst of stale alerts.
    func rebaseline() {
        lastSnapshot = nil
    }

    /// Consumes the stop-is-next one-shot when the backend pushed that alert.
    func markStopIsNextHandled() {
        didNotifyStopIsNext = true
    }

    /// Clears a pended "departing soon" reminder once departure is confirmed
    /// elsewhere — without this it can fire after the train has left.
    func clearDepartureReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["\(serviceId)-departing-soon"])
    }

    func reset() {
        lastSnapshot = nil
        didNotifyStopIsNext = false
        scheduledReminderKey = nil
        // Dynamic identifiers embed platform numbers, times, and station
        // names, so enumerate pending requests and match on the service
        // prefix rather than guessing exact ids.
        let prefix = serviceId
        guard !prefix.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !ours.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ours)
            }
        }
    }

    /// Time-sensitive by default: every immediate alert the app still sends
    /// is an exception the user must act on (platform change, cancellation,
    /// your stop next) — routine progress lives in the Live Activity and
    /// never reaches here while one is showing.
    private func scheduleNotification(
        id: String, title: String, body: String,
        interruption: UNNotificationInterruptionLevel = .timeSensitive
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = serviceId
        content.interruptionLevel = interruption

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification scheduling failed (\(id)): \(error)")
            }
        }
    }

    private func normalizedPlatform(_ p: String?) -> String? {
        guard let p, !p.isEmpty, p != "—" else { return nil }
        return p.trimmingCharacters(in: .whitespaces)
    }

    private func isClockTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":")
        return parts.count == 2 && Int(parts[0]) != nil && Int(parts[1]) != nil
    }
}
