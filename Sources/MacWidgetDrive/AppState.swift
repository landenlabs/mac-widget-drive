import Foundation
import AppKit

struct ScreenPosition: Codable, Equatable {
    var x: Double
    var y: Double
}

/// Identifies the current set of physically-connected displays so the widget
/// can remember a separate position for each monitor arrangement.
enum ScreenFingerprint {
    static var current: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let ids = NSScreen.screens
            .compactMap { $0.deviceDescription[key] as? NSNumber }
            .map { $0.uint32Value }
            .sorted()
        return ids.isEmpty ? "none" : ids.map(String.init).joined(separator: "|")
    }
}

/// Persisted settings plus the runtime traffic-check result, observed by the
/// widget view, the status bar menu, and the refresh scheduler.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool { didSet { save() } }
    @Published var widgetX: Double { didSet { save() } }
    @Published var widgetY: Double { didSet { save() } }
    @Published var screenPositions: [String: ScreenPosition] { didSet { save() } }
    @Published var originAddress: String { didSet { save() } }
    @Published var destinationAddress: String { didSet { save() } }
    @Published var refreshIntervalMinutes: Int { didSet { save() } }

    // Runtime only — not persisted.
    @Published var driveMinutes: Int?
    @Published var previousDriveMinutes: Int?
    @Published var lastChecked: Date?
    @Published var lastError: String?
    @Published var isRefreshing: Bool = false

    var positionX: Double { screenPositions[ScreenFingerprint.current]?.x ?? widgetX }
    var positionY: Double { screenPositions[ScreenFingerprint.current]?.y ?? widgetY }

    private struct Persisted: Codable {
        var isEnabled: Bool
        var widgetX: Double
        var widgetY: Double
        var screenPositions: [String: ScreenPosition]
        var originAddress: String
        var destinationAddress: String
        var refreshIntervalMinutes: Int

        enum CodingKeys: String, CodingKey {
            case isEnabled, widgetX, widgetY, screenPositions, originAddress, destinationAddress, refreshIntervalMinutes
        }

        init(isEnabled: Bool, widgetX: Double, widgetY: Double, screenPositions: [String: ScreenPosition],
             originAddress: String, destinationAddress: String, refreshIntervalMinutes: Int) {
            self.isEnabled = isEnabled
            self.widgetX = widgetX
            self.widgetY = widgetY
            self.screenPositions = screenPositions
            self.originAddress = originAddress
            self.destinationAddress = destinationAddress
            self.refreshIntervalMinutes = refreshIntervalMinutes
        }

        // Tolerates settings.json files written before the route/interval
        // fields existed, so upgrading doesn't reset saved position.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
            widgetX = try c.decodeIfPresent(Double.self, forKey: .widgetX) ?? 0
            widgetY = try c.decodeIfPresent(Double.self, forKey: .widgetY) ?? 0
            screenPositions = try c.decodeIfPresent([String: ScreenPosition].self, forKey: .screenPositions) ?? [:]
            originAddress = try c.decodeIfPresent(String.self, forKey: .originAddress) ?? TrafficService.defaultOriginAddress
            destinationAddress = try c.decodeIfPresent(String.self, forKey: .destinationAddress) ?? TrafficService.defaultDestinationAddress
            refreshIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 10
        }
    }

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("MacWidgetDrive")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            isEnabled = saved.isEnabled
            widgetX = saved.widgetX
            widgetY = saved.widgetY
            screenPositions = saved.screenPositions
            originAddress = saved.originAddress
            destinationAddress = saved.destinationAddress
            refreshIntervalMinutes = saved.refreshIntervalMinutes
        } else {
            isEnabled = true
            widgetX = 0
            widgetY = 0
            screenPositions = [:]
            originAddress = TrafficService.defaultOriginAddress
            destinationAddress = TrafficService.defaultDestinationAddress
            refreshIntervalMinutes = 10
        }
    }

    private func save() {
        let persisted = Persisted(isEnabled: isEnabled, widgetX: widgetX, widgetY: widgetY, screenPositions: screenPositions,
                                   originAddress: originAddress, destinationAddress: destinationAddress,
                                   refreshIntervalMinutes: refreshIntervalMinutes)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func updatePosition(x: Double, y: Double) {
        widgetX = x
        widgetY = y
        screenPositions[ScreenFingerprint.current] = ScreenPosition(x: x, y: y)
    }

    // MARK: - Traffic refresh

    /// Applies edited addresses, clears the stale reading for the old route, and checks the new one.
    func updateRoute(origin: String, destination: String) {
        let origin = origin.trimmingCharacters(in: .whitespaces)
        let destination = destination.trimmingCharacters(in: .whitespaces)
        guard !origin.isEmpty, !destination.isEmpty else { return }
        originAddress = origin
        destinationAddress = destination
        driveMinutes = nil
        previousDriveMinutes = nil
        lastError = nil
        lastChecked = nil
        refreshNow()
    }

    /// Manual or scheduled drive-time check. Safe to call while a check is already in flight.
    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        TrafficService.shared.fetchDriveTime(from: originAddress, to: destinationAddress) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let seconds):
                    self.previousDriveMinutes = self.driveMinutes
                    self.driveMinutes = Int((seconds / 60).rounded())
                    self.lastChecked = Date()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }
}
