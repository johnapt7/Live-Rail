import ActivityKit
import WidgetKit
import SwiftUI

struct TrainTrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainTrackingAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(URL(string: "liverail://journey/\(context.attributes.serviceId)")!)
                // The app's hero look: bright status-coloured card with dark
                // ink text, identical in both appearances.
                .activityBackgroundTint(WidgetTheme.background(for: context.state.status))
                .activitySystemActionForegroundColor(WidgetTheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.operatorCode)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    islandStatusLabel(context.state.status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    let atTerminus = context.state.progressFraction >= 1.0
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context.state.hasDeparted ? "FROM" : "DEPARTING")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .tracking(1.0)
                                    .foregroundStyle(.secondary)
                                Text(context.state.currentStopName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(atTerminus ? "ARRIVED" : "NEXT")
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .tracking(1.0)
                                    .foregroundStyle(.secondary)
                                Text(context.state.nextStopName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                        }

                        progressBar(for: context.state, tint: islandStatusColor(context.state.status))

                        HStack {
                            if atTerminus {
                                Text("Arrived")
                                    .font(.system(size: 11, weight: .semibold))
                            } else if !context.state.hasDeparted {
                                Text(context.state.isBoarding
                                    ? "Boarding · \(context.attributes.scheduledDeparture)"
                                    : "Departs \(context.attributes.scheduledDeparture)")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                countdownLabel(for: context.state)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 3) {
                                if let d = context.state.destinationDelayMinutes, d != 0 {
                                    WidgetDelayChip(minutes: d, onHero: false)
                                }
                                if let eta = context.state.destinationArrivalDate {
                                    Text(eta, style: .time)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .monospacedDigit()
                                } else {
                                    Text(context.attributes.scheduledArrival)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(islandStatusColor(context.state.status))
            } compactTrailing: {
                if context.state.hasDeparted {
                    compactCountdown(for: context.state)
                } else {
                    Text(context.attributes.scheduledDeparture)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(islandStatusColor(context.state.status))
            }
        }
    }

    // MARK: - Lock screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TrainTrackingAttributes>) -> some View {
        let atTerminus = context.state.progressFraction >= 1.0
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(context.attributes.operatorCode)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(WidgetTheme.cream)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WidgetTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(context.attributes.operatorName)
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetTheme.inkSoft)
                    .lineLimit(1)
                Spacer()
                statusPill(context.state.status)
            }

            HStack(alignment: .top, spacing: 12) {
                stopColumn(
                    label: context.state.hasDeparted ? "DEPARTED FROM" : "DEPARTING FROM",
                    name: context.state.currentStopName,
                    time: nil,
                    platform: context.state.hasDeparted ? nil : context.state.platform,
                    delayMinutes: nil,
                    trailing: false
                )
                stopColumn(
                    label: atTerminus ? "ARRIVED AT" : "NEXT STOP",
                    name: context.state.nextStopName,
                    time: context.state.nextStopExpectedTime,
                    platform: context.state.nextStopPlatform,
                    delayMinutes: context.state.nextStopDelayMinutes,
                    trailing: true
                )
            }

            progressBar(for: context.state, tint: WidgetTheme.ink)

            sentenceFooter(context: context, atTerminus: atTerminus)
        }
        .padding(16)
        .foregroundStyle(WidgetTheme.ink)
    }

    @ViewBuilder
    private func stopColumn(label: String, name: String, time: String?, platform: String?, delayMinutes: Int?, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(WidgetTheme.inkSoft)
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let time, !time.isEmpty {
                    Text(time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(WidgetTheme.inkSoft)
                }
                if let d = delayMinutes, d != 0 {
                    WidgetDelayChip(minutes: d, onHero: true)
                }
                if let p = platform, !p.isEmpty, p != "—" {
                    Text("PLAT \(p)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(WidgetTheme.ink.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    @ViewBuilder
    private func sentenceFooter(context: ActivityViewContext<TrainTrackingAttributes>, atTerminus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if atTerminus {
                    Text("Arrived at \(context.state.nextStopName)")
                } else if !context.state.hasDeparted {
                    Text(context.state.isBoarding
                        ? "Boarding · departs \(context.attributes.scheduledDeparture)"
                        : "Departs \(context.attributes.scheduledDeparture)")
                } else if let arrival = context.state.nextStopArrivalDate {
                    let remaining = arrival.timeIntervalSinceNow
                    if remaining < 30 && remaining > -120 {
                        Text("Approaching \(context.state.nextStopName)")
                    } else if remaining > 0 {
                        Text("Arrives at \(context.state.nextStopName) in \(formatRemaining(remaining))")
                    } else {
                        Text("Due now at \(context.state.nextStopName)")
                    }
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .tracking(-0.1)

            if !atTerminus {
                HStack(spacing: 5) {
                    if let d = context.state.destinationDelayMinutes, d > 0 {
                        Text("+\(d) MIN LATE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    Text("Due \(context.attributes.destination)")
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetTheme.inkSoft)
                        .lineLimit(1)
                    if let eta = context.state.destinationArrivalDate {
                        Text(eta, style: .time)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(WidgetTheme.inkSoft)
                    } else {
                        Text(context.attributes.scheduledArrival)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(WidgetTheme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    // Self-updating freshness: stale data announces itself
                    // instead of masquerading as live.
                    (Text("Updated ") + Text(context.state.lastUpdated, style: .relative) + Text(" ago"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(WidgetTheme.inkSoft.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func progressBar(for state: TrainTrackingAttributes.ContentState, tint: Color) -> some View {
        Group {
            if let prev = state.previousStopDepartureDate,
               let next = state.nextStopArrivalDate,
               prev < next {
                ProgressView(timerInterval: prev...next, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
            } else {
                ProgressView(value: max(0, min(state.progressFraction, 1)))
            }
        }
        .tint(tint)
    }

    @ViewBuilder
    private func countdownLabel(for state: TrainTrackingAttributes.ContentState) -> some View {
        if let arrival = state.nextStopArrivalDate {
            let secondsUntil = arrival.timeIntervalSinceNow
            if secondsUntil < 30 && secondsUntil > -120 {
                Text("Approaching")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(islandStatusColor(state.status))
            } else if secondsUntil > 0 {
                Text(formatRemaining(secondsUntil))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text("Now")
                    .font(.system(size: 11, weight: .semibold))
            }
        } else {
            Text(state.nextStopExpectedTime)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    @ViewBuilder
    private func compactCountdown(for state: TrainTrackingAttributes.ContentState) -> some View {
        if let arrival = state.nextStopArrivalDate {
            let secondsUntil = arrival.timeIntervalSinceNow
            if secondsUntil > 0 && secondsUntil < 60 {
                // Last minute: tight MM:SS countdown. Timer-style Text claims
                // unbounded width inside the Dynamic Island, which balloons the
                // compact pill to full screen width — pin it to the exact size
                // of "0:59" so the island stays a pill.
                Text(timerInterval: Date()...arrival, countsDown: true, showsHours: false)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 34)
                    .multilineTextAlignment(.trailing)
            } else if secondsUntil > 0 {
                // Otherwise: just minute count, no live tick (saves width)
                let totalMinutes = Int((secondsUntil + 30) / 60)
                let hours = totalMinutes / 60
                let mins = totalMinutes % 60
                if hours > 0 {
                    Text("\(hours)h\(mins > 0 ? "\(mins)" : "")")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } else {
                    Text("\(mins)m")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            } else {
                Text("now")
                    .font(.system(size: 11, weight: .semibold))
            }
        } else {
            Text(state.nextStopExpectedTime)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds + 30) / 60)
        if totalMinutes < 1 { return "<1 min" }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    /// Capsule status pill matching the app's StatusPill: lime for on time,
    /// dark amber pill when delayed, red pill when cancelled.
    @ViewBuilder
    private func statusPill(_ status: String) -> some View {
        let (bg, fg, label): (Color, Color, String) = {
            switch status {
            case "cancelled": return (WidgetTheme.cancelledPillBg, WidgetTheme.cancelledPillFg, "Cancelled")
            case "delayed": return (WidgetTheme.delayedPillBg, WidgetTheme.delayedPillFg, "Delayed")
            default: return (WidgetTheme.onTimeBg, WidgetTheme.onTimeFg, "On time")
            }
        }()
        HStack(spacing: 4) {
            Circle()
                .fill(fg)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.2)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(bg)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func islandStatusLabel(_ status: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(islandStatusColor(status))
                .frame(width: 6, height: 6)
            Text(status == "on-time" ? "On time" : status == "delayed" ? "Delayed" : "Cancelled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// Status colours on the island's black pill — the app accent for on
    /// time (not system green), dark-surface amber/red otherwise. Fixed:
    /// the island never changes appearance with the system scheme.
    private func islandStatusColor(_ status: String) -> Color {
        switch status {
        case "delayed": return WidgetTheme.islandDelayed
        case "cancelled": return WidgetTheme.islandCancelled
        default: return WidgetTheme.islandAccent
        }
    }
}

private struct WidgetDelayChip: View {
    let minutes: Int
    /// On the bright hero card the chip is ink-on-ink-wash (the background
    /// already carries the status colour); on the island it keeps semantic
    /// colour against black.
    let onHero: Bool

    var body: some View {
        let color: Color = onHero
            ? WidgetTheme.ink
            : (minutes > 0 ? WidgetTheme.islandDelayed : .green)
        Text(minutes > 0 ? "+\(minutes)" : "\(minutes)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(onHero ? 0.10 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
