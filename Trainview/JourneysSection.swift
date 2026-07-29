import SwiftUI

/// Journey-first search results: when a destination filter is active, the
/// board shows complete journeys — direct and via a change, mixed and in
/// departure order — from the backend planner, instead of a direct-only
/// train list with a buried transfer fallback.
struct JourneysSection: View {
    let origin: Station
    let destination: Station
    let accent: Color
    let onOpenTrain: (Train) -> Void

    @State private var options: [JourneyOption] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTransfer: TransferOption?
    /// Leg 1 queued for tracking; the push fires in the sheet's onDismiss —
    /// a navigation push mid-dismissal can be swallowed by SwiftUI.
    @State private var pendingLeg1: BoardService?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .task(id: origin.code + ":" + destination.code) {
            await load()
        }
        // Silent refresh keeps delays and platforms current; jittered so
        // phones don't synchronise into bursts at the backend.
        .task(id: origin.code + ":" + destination.code + ":refresh") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45 * Double.random(in: 0.85...1.15)))
                guard !Task.isCancelled else { break }
                await load(silent: true)
            }
        }
        .sheet(item: $selectedTransfer, onDismiss: {
            if let leg1 = pendingLeg1 {
                pendingLeg1 = nil
                onOpenTrain(Train(from: leg1))
            }
        }) { option in
            TransferJourneyScreen(
                option: option,
                originName: origin.name,
                destinationName: destination.name,
                accent: accent
            ) {
                pendingLeg1 = option.leg1
                selectedTransfer = nil
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkMute)
                Text("JOURNEYS")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkMute)
            }
            Spacer()
            if !options.isEmpty {
                Text("\(options.count) found")
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(Theme.inkMute)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.ink.opacity(0.06))
                        .frame(height: 76)
                        .shimmer()
                }
            }
        } else if let error = loadError {
            VStack(spacing: 8) {
                Text(error)
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkMute)
                Button {
                    Task { await load() }
                } label: {
                    Text("Try again")
                        .font(.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(accent)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if options.isEmpty {
            VStack(spacing: 4) {
                Text("No journeys found")
                    .font(.display(18))
                Text("Nothing direct or via a change to \(destination.name) in the next couple of hours")
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkMute)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 10) {
                ForEach(options) { option in
                    JourneyOptionCard(option: option, accent: accent) {
                        open(option)
                    }
                }
            }
        }
    }

    private func open(_ option: JourneyOption) {
        if option.legs.count == 2, let transfer = transferOption(for: option) {
            selectedTransfer = transfer
        } else if let leg = option.legs.first {
            onOpenTrain(Train(from: leg.asBoardService()))
        }
    }

    /// A planner option reshaped into the transfer model so the two-leg
    /// overview (and the tracking pipeline behind it) can be reused as-is.
    private func transferOption(for option: JourneyOption) -> TransferOption? {
        guard option.legs.count == 2 else { return nil }
        let l1 = option.legs[0]
        let l2 = option.legs[1]
        let arriveChange = TimeFormat.parseClockTime(l1.expectedArrival) ?? l1.scheduledArrival
        let departChange = TimeFormat.parseClockTime(l2.expectedDeparture) ?? l2.scheduledDeparture
        // The change station as leg 2's first "previous" point, so the
        // overview can read the platform and slice the intermediate stops.
        let changePoint = CallingPointResponse(
            station: l1.destination.name,
            crs: l1.destination.crs,
            scheduledTime: l2.scheduledDeparture,
            expectedTime: nil,
            actualTime: nil,
            platform: l2.origin.platform,
            isCancelled: false,
            status: l2.status
        )
        let leg2Previous = [changePoint] + (l2.callingPoints ?? []).dropLast()
        return TransferOption(
            leg1: l1.asBoardService(),
            changeCrs: l1.destination.crs,
            changeName: l1.destination.name,
            leg1ArrivalAtChange: arriveChange,
            leg2: l2.asBoardService(previousPoints: leg2Previous),
            leg2DepartureAtChange: departChange,
            arrivalAtDestination: TimeFormat.parseClockTime(l2.expectedArrival) ?? l2.scheduledArrival,
            waitMinutes: TransferPlanner.minutesBetween(arriveChange, departChange) ?? 0
        )
    }

    private func load(silent: Bool = false) async {
        if !silent {
            isLoading = options.isEmpty
            loadError = nil
        }
        do {
            let response = try await APIClient.shared.planJourney(from: origin.code, to: destination.code)
            withAnimation(silent ? nil : .easeOut(duration: 0.3)) {
                options = response.options ?? []
                loadError = nil
            }
        } catch {
            if !silent {
                loadError = "Couldn't load journeys."
                options = []
            }
        }
        isLoading = false
    }
}

// MARK: - Option card

/// One journey option: times and duration up top, the shape of the journey
/// (direct, or where the change happens and how long it allows) below.
struct JourneyOptionCard: View {
    let option: JourneyOption
    let accent: Color
    let onTap: () -> Void

    private var isCancelled: Bool { option.status == "cancelled" }
    private var isDelayed: Bool { option.status.contains("delays") }

    private var durationLabel: String {
        let m = option.totalDurationMinutes
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    private var changeSummary: String? {
        guard option.legs.count == 2 else { return nil }
        let l1 = option.legs[0]
        let l2 = option.legs[1]
        let arrive = TimeFormat.parseClockTime(l1.expectedArrival) ?? l1.scheduledArrival
        let depart = TimeFormat.parseClockTime(l2.expectedDeparture) ?? l2.scheduledDeparture
        if let wait = TransferPlanner.minutesBetween(arrive, depart) {
            return "change at \(l1.destination.name.decodingHTMLEntities()) · \(wait) min wait"
        }
        return "change at \(l1.destination.name.decodingHTMLEntities())"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(option.departureTime)
                        .font(.mono(17, weight: .semibold))
                        .foregroundStyle(isCancelled ? Theme.cancelledText : (isDelayed ? Theme.delayedText : Theme.ink))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                    Text(option.arrivalTime)
                        .font(.mono(17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(durationLabel)
                        .font(.mono(11, weight: .medium))
                        .foregroundStyle(Theme.inkMute)
                        .padding(.leading, 2)
                    Spacer()
                    if isCancelled {
                        CodeTag(text: "CANCELLED", bg: Theme.cancelledText, fg: Theme.cream)
                    } else if option.isDirect {
                        CodeTag(text: "DIRECT")
                    } else {
                        CodeTag(text: "1 CHANGE", bg: accent, fg: Theme.ink)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(Array(option.legs.enumerated()), id: \.offset) { index, leg in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.inkMute)
                        }
                        let brand = OperatorBrand.brand(for: leg.operatorCode)
                        Text(leg.operatorCode)
                            .font(.mono(9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(brand.fg)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(brand.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(changeSummary ?? "towards \(option.legs.first.map { ($0.serviceDestination ?? $0.destination.name).decodingHTMLEntities() } ?? "")")
                        .font(.ui(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                }

                if let warning = option.warnings?.first {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(warning)
                            .font(.ui(11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.delayedText)
                }
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(isCancelled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Leg bridging

extension JourneyLegResponse {
    /// The leg as a board row — lets journey legs flow into the existing
    /// Train / tracking pipeline unchanged.
    func asBoardService(previousPoints: [CallingPointResponse]? = nil) -> BoardService {
        BoardService(
            scheduledTime: scheduledDeparture,
            expectedTime: expectedDeparture,
            platform: origin.platform,
            predictedPlatform: nil,
            operator: `operator`,
            operatorCode: operatorCode,
            destination: serviceDestination ?? destination.name,
            destinationCrs: "",
            destinationVia: nil,
            origin: origin.name,
            originCrs: origin.crs,
            isCancelled: isCancelled,
            cancelReason: cancelReason,
            delayReason: delayReason,
            serviceId: serviceId,
            length: nil,
            status: status,
            rid: nil,
            uid: nil,
            headcode: nil,
            subsequentCallingPoints: callingPoints,
            previousCallingPoints: previousPoints,
            rollingStock: nil
        )
    }
}
