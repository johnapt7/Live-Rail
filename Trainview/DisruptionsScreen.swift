import SwiftUI

/// Network status: what's wrong at YOUR stations first, then every
/// operator. Disrupted operators expand to say what's actually happening,
/// with a link to their live travel news.
struct DisruptionsScreen: View {
    let accent: Color

    @State private var indicators: [TOCIndicator] = []
    @State private var indicatorsLoaded = false
    @State private var loadError = false
    @State private var stationReports: [StationDisruptionsResponse] = []
    @State private var stationsChecked = false
    @State private var expandedOperator: String?
    @State private var expandedDisruption: String?

    private var disrupted: [TOCIndicator] {
        indicators.filter { $0.status != "Good service" }
    }

    private var healthy: [TOCIndicator] {
        indicators.filter { $0.status == "Good service" }
    }

    private var homeStations: [Station] { HomeStationsStore.shared.stations }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if loadError {
                        errorCard
                    } else if !indicatorsLoaded {
                        loadingCard
                    } else {
                        summaryHeader
                        if !homeStations.isEmpty {
                            yourStationsSection
                        }
                        operatorList
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Theme.cream)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        Text("DISRUPTIONS")
            .font(.mono(11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Theme.cream)
    }

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            Text("\(indicators.count)")
                .font(.display(42))
                .tracking(-1)
            VStack(alignment: .leading, spacing: 0) {
                Text("operators")
                Text("tracked")
            }
            .font(.mono(11))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSoft)
            Spacer()
            if disrupted.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("All clear")
                        .font(.mono(11, weight: .semibold))
                        .tracking(0.4)
                }
                .foregroundStyle(Theme.perfGood)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.perfGood.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Text("\(disrupted.count) disrupted")
                    .font(.mono(11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.delayedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.warn.opacity(0.3))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - Your stations

    /// Live incident messages for the user's home stations — the part of
    /// the network they actually stand on. All-clear collapses to one line.
    @ViewBuilder
    private var yourStationsSection: some View {
        let reports = stationReports.filter { !$0.disruptions.isEmpty }
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR STATIONS")
                .font(.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.inkMute)
                .padding(.horizontal, 4)
            if !stationsChecked {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.ink)
                    Text("Checking \(homeStations.count) station\(homeStations.count == 1 ? "" : "s")…")
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if reports.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.perfGood)
                    Text("No incidents reported at \(homeStations.map(\.name).joined(separator: ", "))")
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(reports, id: \.crs) { report in
                    stationReportCard(report)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }

    private func stationReportCard(_ report: StationDisruptionsResponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CodeTag(text: report.crs)
                Text(report.stationName)
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(report.disruptions.count)")
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.delayedText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            ForEach(report.disruptions) { disruption in
                Divider().overlay(Theme.line)
                stationDisruptionRow(disruption, stationCode: report.crs)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.warn.opacity(0.5), lineWidth: 1)
        )
    }

    private func stationDisruptionRow(_ disruption: StationDisruption, stationCode: String) -> some View {
        let key = stationCode + disruption.id
        let expanded = expandedDisruption == key
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                expandedDisruption = expanded ? nil : key
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(disruption.title)
                        .font(.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                if expanded {
                    Text(disruption.description)
                        .font(.ui(12))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let advice = disruption.customerAdvice, !advice.isEmpty {
                        Text(advice)
                            .font(.ui(12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Operators

    /// Disrupted operators surface first and expand to say what's actually
    /// happening; healthy rows stay one glanceable line.
    private var operatorList: some View {
        VStack(spacing: 0) {
            ForEach(Array((disrupted + healthy).enumerated()), id: \.element.tocCode) { index, toc in
                operatorRow(toc)
                    .overlay(alignment: .bottom) {
                        if index < indicators.count - 1 {
                            Divider().overlay(Theme.line)
                        }
                    }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 20)
    }

    @ViewBuilder
    private func operatorRow(_ toc: TOCIndicator) -> some View {
        let brand = OperatorBrand.brand(for: toc.tocCode)
        let isGood = toc.status == "Good service"
        let expanded = expandedOperator == toc.tocCode

        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !isGood else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedOperator = expanded ? nil : toc.tocCode
                }
            } label: {
                HStack(spacing: 10) {
                    Text(toc.tocCode)
                        .font(.mono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(brand.fg)
                        .frame(width: 32, height: 26)
                        .background(brand.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toc.tocName)
                            .font(.ui(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if !isGood {
                            Text(toc.status)
                                .font(.ui(11))
                                .foregroundStyle(Theme.delayedText)
                                .lineLimit(expanded ? nil : 1)
                        }
                    }
                    Spacer()
                    // Fixed slot whether or not a chevron shows, so the
                    // status dots form one straight column down the list.
                    Group {
                        if !isGood {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.inkMute)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 12, height: 12)
                    Circle()
                        .fill(isGood ? Theme.perfGood : Theme.cancelledText)
                        .frame(width: 10, height: 10)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !toc.statusDescription.isEmpty {
                        Text(toc.statusDescription)
                            .font(.ui(12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let info = toc.additionalInfo, !info.isEmpty {
                        Text(info)
                            .font(.ui(12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let urlString = toc.detailURL, let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(spacing: 5) {
                                Text("Live travel news")
                                    .font(.ui(12, weight: .semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.35))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Loading & error

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Theme.ink)
            Text("Checking the network...")
                .font(.ui(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var errorCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18))
                .foregroundStyle(Theme.inkMute)
                .padding(.bottom, 2)
            Text("Couldn't load network status")
                .font(.display(18))
            Text("Check your connection and try again")
                .font(.ui(11))
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
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: - Data

    private func load() async {
        loadError = false
        do {
            indicators = try (await APIClient.shared.getTOCIndicators()).indicators
            indicatorsLoaded = true
        } catch {
            if !indicatorsLoaded { loadError = true }
        }
        await loadStationReports()
    }

    /// One fetch per home station, concurrently; a station whose fetch
    /// fails simply reports no incidents rather than blocking the screen.
    private func loadStationReports() async {
        let stations = homeStations
        guard !stations.isEmpty else {
            stationsChecked = true
            return
        }
        var reports: [StationDisruptionsResponse] = []
        await withTaskGroup(of: StationDisruptionsResponse?.self) { group in
            for station in stations {
                group.addTask {
                    try? await APIClient.shared.getStationDisruptions(crs: station.code)
                }
            }
            for await report in group {
                if let report { reports.append(report) }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: stations.enumerated().map { ($0.element.code, $0.offset) })
        withAnimation(.easeOut(duration: 0.2)) {
            stationReports = reports.sorted { (order[$0.crs] ?? 99) < (order[$1.crs] ?? 99) }
            stationsChecked = true
        }
    }
}
