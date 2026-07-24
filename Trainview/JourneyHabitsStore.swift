import Foundation

/// A journey the user has tracked often enough from one station that the app
/// surfaces it automatically when they arrive there.
struct JourneyHabit: Equatable {
    let stationCode: String
    let stationName: String
    let latitude: Double
    let longitude: Double
    let destinationCode: String
    let destinationName: String
    let count: Int
}

/// Counts every tracked journey per boarding station. Five tracks of the
/// same journey make that station's habit; the habit always follows the
/// MOST-tracked destination, so a changed commute retargets it naturally.
@Observable
final class JourneyHabitsStore {
    static let shared = JourneyHabitsStore()

    /// Tracks of one journey from one station before it becomes a habit.
    static let habitThreshold = 5
    /// iOS caps monitored regions at 20 per app; stay well inside it.
    private static let maxHabitStations = 10
    private static let storageKey = "journeyHabits.v1"

    private struct DestinationRecord: Codable {
        var name: String
        var count: Int
    }

    private struct StationRecord: Codable {
        var name: String
        var latitude: Double?
        var longitude: Double?
        var destinations: [String: DestinationRecord]
    }

    private var stations: [String: StationRecord] = [:]
    /// Notified after any mutation that can change the qualifying habit set.
    var onHabitsChanged: () -> Void = {}

    init() {
        load()
    }

    /// Records one tracked journey. Station coordinates arrive lazily from
    /// the API the first time a station is seen — the geofence needs them.
    func recordTracking(boarding: Station, destinationCode: String, destinationName: String) {
        guard !boarding.code.isEmpty, !destinationCode.isEmpty,
              boarding.code != destinationCode else { return }
        var record = stations[boarding.code]
            ?? StationRecord(name: boarding.name, latitude: nil, longitude: nil, destinations: [:])
        record.name = boarding.name
        var destination = record.destinations[destinationCode]
            ?? DestinationRecord(name: destinationName, count: 0)
        destination.name = destinationName
        destination.count += 1
        record.destinations[destinationCode] = destination
        stations[boarding.code] = record
        save()
        if record.latitude == nil {
            resolveCoordinates(for: boarding.code)
        }
        onHabitsChanged()
    }

    /// The station's habit: its most-tracked destination, once tracked at
    /// least `habitThreshold` times. Ties break on the destination code so
    /// the result is stable between launches.
    func habit(for stationCode: String) -> JourneyHabit? {
        guard let record = stations[stationCode],
              let latitude = record.latitude, let longitude = record.longitude,
              let best = record.destinations.max(by: {
                  ($0.value.count, $1.key) < ($1.value.count, $0.key)
              }),
              best.value.count >= Self.habitThreshold else { return nil }
        return JourneyHabit(
            stationCode: stationCode,
            stationName: record.name,
            latitude: latitude,
            longitude: longitude,
            destinationCode: best.key,
            destinationName: best.value.name,
            count: best.value.count
        )
    }

    /// Qualifying habits for geofence registration, strongest first.
    func qualifyingHabits() -> [JourneyHabit] {
        let habits = stations.keys.compactMap { habit(for: $0) }
        return Array(habits.sorted { ($0.count, $1.stationCode) > ($1.count, $0.stationCode) }
            .prefix(Self.maxHabitStations))
    }

    private func resolveCoordinates(for stationCode: String) {
        Task { @MainActor in
            guard let found = try? await APIClient.shared.searchStations(query: stationCode, limit: 5),
                  let match = found.first(where: { $0.crs == stationCode }),
                  let latitude = match.latitude, let longitude = match.longitude else { return }
            guard var record = self.stations[stationCode] else { return }
            record.latitude = latitude
            record.longitude = longitude
            self.stations[stationCode] = record
            self.save()
            self.onHabitsChanged()
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: StationRecord].self, from: data) else { return }
        stations = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
