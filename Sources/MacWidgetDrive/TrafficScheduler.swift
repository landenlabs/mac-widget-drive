import Foundation
import Combine

/// Owns the repeating check. Restarts itself whenever the enable/disable
/// toggle or the configured interval changes, and runs an immediate check
/// whenever it (re)starts (including at app launch) so the widget doesn't sit
/// blank until the first tick.
final class TrafficScheduler {
    static let shared = TrafficScheduler()

    private var timer: Timer?
    private var cancellable: AnyCancellable?

    func start() {
        let appState = AppState.shared
        cancellable = Publishers.CombineLatest(appState.$isEnabled, appState.$refreshIntervalMinutes)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] enabled, minutes in
                self?.reschedule(enabled: enabled, minutes: minutes)
            }
    }

    private func reschedule(enabled: Bool, minutes: Int) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        AppState.shared.refreshNow()
        let interval = TimeInterval(max(1, minutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            AppState.shared.refreshNow()
        }
    }
}
