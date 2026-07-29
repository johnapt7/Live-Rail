import SwiftUI

/// Two-leg journey overview, shown when the user picks a via-a-change route.
/// The change is the headline: leg 1 runs down to the change station, a
/// change band spells out where and how long, and the second train appears
/// in full — its own departure, calling points, and arrival — so nobody
/// boards without knowing they'll be getting off halfway.
struct TransferJourneyScreen: View {
    let option: TransferOption
    let originName: String
    let destinationName: String
    let accent: Color
    /// Hands leg 1 to the journey screen — the train the user boards first.
    let onTrackLeg1: () -> Void

    private var isTight: Bool { option.waitMinutes < 10 }

    private var departTime: String {
        TimeFormat.parseClockTime(option.leg1.expectedTime) ?? option.leg1.scheduledTime
    }

    /// Leg 1's intermediate stops: after the origin, before the change.
    private var leg1Stops: [CallingPointResponse] {
        let points = option.leg1.subsequentCallingPoints ?? []
        guard let changeIdx = points.firstIndex(where: { $0.crs == option.changeCrs }) else { return [] }
        return Array(points[..<changeIdx])
    }

    /// Leg 2's intermediate stops: after the change, before the destination.
    /// The second train came off the destination's arrivals board, so its
    /// route lives in previousCallingPoints.
    private var leg2Stops: [CallingPointResponse] {
        let points = option.leg2.previousCallingPoints ?? []
        guard let changeIdx = points.firstIndex(where: { $0.crs == option.changeCrs }) else { return [] }
        return Array(points[(changeIdx + 1)...])
    }

    private var changePlatform: String? {
        let points = option.leg2.previousCallingPoints ?? []
        guard let change = points.first(where: { $0.crs == option.changeCrs }),
              let platform = change.platform, !platform.isEmpty, platform != "—" else { return nil }
        return platform
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    legCard(
                        service: option.leg1,
                        boardName: originName,
                        boardTime: departTime,
                        boardPlatform: option.leg1.platform,
                        stops: leg1Stops,
                        alightName: option.changeName,
                        alightTime: option.leg1ArrivalAtChange,
                        alightPlatform: nil
                    )
                    changeBand
                    legCard(
                        service: option.leg2,
                        boardName: option.changeName,
                        boardTime: option.leg2DepartureAtChange,
                        boardPlatform: changePlatform,
                        stops: leg2Stops,
                        alightName: destinationName,
                        alightTime: option.arrivalAtDestination,
                        alightPlatform: nil
                    )
                }
                .padding(18)
                .padding(.bottom, 8)
            }
            trackButton
        }
        .background(Theme.cream)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("JOURNEY WITH A CHANGE")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkMute)
                Spacer()
                CodeTag(text: "1 CHANGE", bg: accent, fg: Theme.ink)
            }
            HStack(spacing: 8) {
                Text(departTime)
                    .font(.mono(22, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
                Text(option.arrivalAtDestination)
                    .font(.mono(22, weight: .semibold))
                if let duration = TimeFormat.journeyDuration(from: departTime, to: option.arrivalAtDestination) {
                    Text(duration)
                        .font(.mono(12, weight: .medium))
                        .foregroundStyle(Theme.inkMute)
                        .padding(.leading, 2)
                }
            }
            .foregroundStyle(Theme.ink)
            Text("\(originName) to \(destinationName.decodingHTMLEntities())")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: - Change band

    private var changeBand: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("CHANGE AT \(option.changeName.uppercased())")
                    .font(.mono(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.ink)
                Text(isTight
                    ? "Only \(option.waitMinutes) min — head straight to your next train"
                    : "\(option.waitMinutes) min to make the change")
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background((isTight ? Theme.warn : accent).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isTight ? Theme.warn : accent, lineWidth: 1.5)
        )
    }

    // MARK: - Leg card

    private func legCard(
        service: BoardService,
        boardName: String,
        boardTime: String,
        boardPlatform: String?,
        stops: [CallingPointResponse],
        alightName: String,
        alightTime: String,
        alightPlatform: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                let brand = OperatorBrand.brand(for: service.operatorCode)
                Text(service.operatorCode)
                    .font(.mono(9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(brand.fg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(brand.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(service.operator)
                    .font(.ui(12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                Spacer()
                Text("towards \(service.destination.decodingHTMLEntities())")
                    .font(.ui(11))
                    .foregroundStyle(Theme.inkMute)
                    .lineLimit(1)
            }

            endpointRow(time: boardTime, name: boardName, platform: boardPlatform, isBoarding: true)
            ForEach(stops) { stop in
                stopRow(stop)
            }
            endpointRow(time: alightTime, name: alightName, platform: alightPlatform, isBoarding: false)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func endpointRow(time: String, name: String, platform: String?, isBoarding: Bool) -> some View {
        HStack(spacing: 10) {
            Text(time)
                .font(.mono(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Circle()
                .fill(accent)
                .stroke(Theme.ink, lineWidth: 1.5)
                .frame(width: 11, height: 11)
            Text(name.decodingHTMLEntities())
                .font(.display(16))
                .tracking(-0.2)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer()
            if let platform, !platform.isEmpty, platform != "—" {
                Text("Plat. \(platform)")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(Theme.inkMute)
            }
            CodeTag(text: isBoarding ? "BOARD" : "ALIGHT", bg: isBoarding ? Theme.ink : accent, fg: isBoarding ? Theme.cream : Theme.ink)
        }
    }

    private func stopRow(_ stop: CallingPointResponse) -> some View {
        HStack(spacing: 10) {
            Text(TransferPlanner.bestTime(stop) ?? stop.scheduledTime)
                .font(.mono(11))
                .foregroundStyle(Theme.inkMute)
                .frame(width: 38, alignment: .leading)
            Circle()
                .fill(Theme.inkMute.opacity(0.5))
                .frame(width: 5, height: 5)
                .padding(.leading, 3)
            Text(stop.station.decodingHTMLEntities())
                .font(.ui(12))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, 2)
    }

    // MARK: - Track button

    private var trackButton: some View {
        Button(action: onTrackLeg1) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                // Named like a platform announcement — "the 15:35 to
                // Weymouth" — so there's no doubt which of the two trains
                // this tracks.
                Text("Track the \(departTime) to \(option.leg1.destination.decodingHTMLEntities())")
                    .font(.ui(15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
