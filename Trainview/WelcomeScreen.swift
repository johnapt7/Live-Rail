import SwiftUI
import CoreLocation

struct WelcomeScreen: View {
    let accent: Color
    let onContinue: () -> Void

    @State private var locationManager = LocationManager()
    @State private var nearestStation: Station?
    @State private var seeding = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                featuresSection
                permissionsSection
                footerSection
            }
        }
        .background(Theme.cream)
        // The accent hero bleeds up behind the status bar.
        .ignoresSafeArea(edges: .top)
        .onChange(of: locationManager.location) { _, coord in
            guard seeding, nearestStation == nil, let coord else { return }
            Task {
                guard let wrapper = try? await APIClient.shared.getNearbyStations(
                    lat: coord.latitude, lng: coord.longitude, limit: 1
                ), let nearest = wrapper.stations?.first else {
                    onContinue()
                    return
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    nearestStation = Station(from: nearest)
                }
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            // Declined the prompt mid-seeding: enter Home without the offer.
            if seeding, locationManager.isDenied {
                onContinue()
            }
        }
    }

    /// A brand-new Home has nothing to show until stations are earned
    /// through use — so the first station is offered here, while location
    /// permission is fresh, and Home demonstrates live departures
    /// immediately.
    private func beginSeeding() {
        guard !seeding else { return }
        if locationManager.isDenied {
            onContinue()
            return
        }
        seeding = true
        locationManager.requestLocation()
        // Watchdog: never hold the user hostage to a slow fix or fetch.
        Task {
            try? await Task.sleep(for: .seconds(7))
            if nearestStation == nil {
                onContinue()
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandMark
            VStack(alignment: .leading, spacing: 10) {
                Text("Live departures, every platform.")
                    .font(.display(32, weight: .semibold))
                    .tracking(-0.6)
                    .lineSpacing(-2)
                Text("A clean, glanceable board for the UK rail network \u{2014} from your nearest station to the last stop on the line.")
                    .font(.ui(13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: 260, alignment: .leading)
            }
            chipRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 62)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 28,
                bottomTrailingRadius: 28, topTrailingRadius: 0
            )
        )
        .foregroundStyle(Theme.ink)
        // Unlike the journey hero, welcome follows the system scheme — a
        // bright teal block on an otherwise warm dark screen read as a
        // leftover, not a signature.
    }

    private var brandMark: some View {
        HStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.system(size: 16))
            Text("TRAINVIEW")
                .font(.mono(11, weight: .semibold))
                .tracking(1.5)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            WelcomeChip(text: "2,500+ stations")
            WelcomeChip(text: "Real-time")
            WelcomeChip(text: "Free")
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "WHAT YOU CAN DO", size: 10, tracking: 1.4)
                .padding(.bottom, 2)
            BulletRow(
                icon: "rectangle.split.3x1.fill",
                title: "Live departure boards",
                detail: "See the next hour of trains from any station \u{2014} platforms, operators, delays, and cancellations updated live.",
                accent: accent
            )
            BulletRow(
                icon: "tram.fill",
                title: "Full journey detail",
                detail: "Tap a service to see every calling point, carriage count, a route map, and live progress between stops.",
                accent: accent
            )
            BulletRow(
                icon: "mappin",
                title: "Find stations near you",
                detail: "Pinned shortcuts, recent stations, and a search of the full network.",
                accent: accent
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "PERMISSIONS WE'LL ASK FOR", size: 10, tracking: 1.4)
            VStack(spacing: 0) {
                PermissionRow(
                    icon: "mappin",
                    title: "Location",
                    detail: "So we can surface stations near you. We never store your location.",
                    required: false
                )
                PermissionRow(
                    icon: "exclamationmark.triangle",
                    title: "Notifications",
                    detail: "Optional alerts for delays, platform changes, and cancellations on the trains you're tracking.",
                    required: false
                )
                PermissionRow(
                    icon: "wifi",
                    title: "Network access",
                    detail: "Required to fetch live timetable and platform data from National Rail and operator feeds.",
                    required: true,
                    showDivider: false
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            if let nearest = nearestStation {
                nearestStationOffer(nearest)
            } else {
                Button(action: beginSeeding) {
                    HStack(spacing: 10) {
                        if seeding {
                            ProgressView()
                                .tint(accent)
                            Text("Finding your nearest station…")
                                .font(.ui(15, weight: .semibold))
                        } else {
                            Text("Get started")
                                .font(.ui(15, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.ink)
                    .clipShape(Capsule())
                }
                .disabled(seeding)
            }

            Text("You can change permissions at any time in Settings.")
        }
        .font(.ui(10.5))
        .foregroundStyle(Theme.inkMute)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private func nearestStationOffer(_ nearest: Station) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("YOUR NEAREST STATION")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkMute)
                Text(nearest.name)
                    .font(.display(20))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.ink)
            }
            Button {
                HomeStationsStore.shared.add(nearest)
                onContinue()
            } label: {
                Text("Add as home station")
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.ink)
                    .clipShape(Capsule())
            }
            Button(action: onContinue) {
                Text("Not now")
                    .font(.ui(13, weight: .medium))
                    .foregroundStyle(Theme.inkMute)
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

// MARK: - Sub-components

private struct WelcomeChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mono(10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct BulletRow: View {
    let icon: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(14, weight: .semibold))
                    .tracking(-0.05)
                Text(detail)
                    .font(.ui(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let required: Bool
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Theme.ink.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.ui(13, weight: .semibold))
                        Text(required ? "REQUIRED" : "OPTIONAL")
                            .font(.mono(9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(required ? Theme.cream : Theme.inkSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(required ? Theme.ink : Theme.ink.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(detail)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .overlay(Theme.line)
            }
        }
    }
}
