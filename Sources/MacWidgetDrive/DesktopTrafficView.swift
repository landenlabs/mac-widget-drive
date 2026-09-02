import SwiftUI

struct DesktopTrafficView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var windowManager: DesktopWindowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            status
        }
        .padding(14)
        .frame(width: 250, height: 108, alignment: .topLeading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if windowManager.isDragging {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isEnabled ? Color.green : Color.red)
                .frame(width: 9, height: 9)
            Text(Self.routeLabel(from: appState.originAddress, to: appState.destinationAddress))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
        }
    }

    @ViewBuilder
    private var status: some View {
        if !appState.isEnabled {
            Text("Paused")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        } else if appState.isRefreshing && appState.driveMinutes == nil {
            Text("Checking\u{2026}")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        } else if let error = appState.lastError, appState.driveMinutes == nil {
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .lineLimit(2)
        } else if let minutes = appState.driveMinutes {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.formattedDuration(minutes))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Self.durationColor(minutes))
                if let previous = appState.previousDriveMinutes {
                    Text(Self.formattedDelta(minutes - previous))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                if appState.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            if let last = appState.lastChecked {
                Text("Updated \(Self.relativeTime(last))")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
        } else {
            Text("\u{2014}")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    /// Drops the street portion of each address (everything before the first
    /// comma) so the header reads e.g. "Boston, MA \u{2192} Salem, NH" instead of
    /// the full street addresses, which won't fit in the widget's width.
    private static func routeLabel(from origin: String, to destination: String) -> String {
        "\(shortAddress(origin)) \u{2192} \(shortAddress(destination))"
    }

    private static func shortAddress(_ address: String) -> String {
        let parts = address.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return address.trimmingCharacters(in: .whitespaces) }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }

    private static func formattedDuration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    private static func formattedDelta(_ delta: Int) -> String {
        ", \(delta >= 0 ? "+" : "-")\(abs(delta)) min"
    }

    /// Green under an hour, yellow from 1:00 up to 1:15, red beyond that.
    private static func durationColor(_ minutes: Int) -> Color {
        if minutes < 60 { return .green }
        if minutes <= 75 { return .yellow }
        return .red
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
