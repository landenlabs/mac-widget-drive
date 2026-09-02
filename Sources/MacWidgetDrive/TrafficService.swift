import Foundation
import CoreLocation
import MapKit
import AppKit

enum TrafficError: LocalizedError {
    case geocodeFailed(String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .geocodeFailed(let address): return "Couldn't locate \"\(address)\""
        case .noRoute: return "No driving route found"
        }
    }
}

/// Looks up current driving time between two addresses via MapKit Directions
/// (includes live traffic conditions). Geocoded placemarks are cached in
/// memory per address string, so re-checking an unchanged route never
/// re-geocodes.
final class TrafficService {
    static let shared = TrafficService()

    static let defaultOriginAddress = "1 Infinite Loop, Cupertino, CA"
    static let defaultDestinationAddress = "1600 Amphitheatre Parkway, Mountain View, CA"

    /// Opens Google Maps driving directions for the given route in the default browser.
    static func openDirectionsInMaps(origin: String, destination: String) {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "travelmode", value: "driving"),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private let geocoder = CLGeocoder()
    private var placemarkCache: [String: CLPlacemark] = [:]

    func fetchDriveTime(from origin: String, to destination: String,
                         completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        resolvePlacemark(for: origin) { [weak self] originResult in
            guard let self else { return }
            switch originResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let originPlacemark):
                self.resolvePlacemark(for: destination) { destinationResult in
                    switch destinationResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let destinationPlacemark):
                        self.route(from: originPlacemark, to: destinationPlacemark, completion: completion)
                    }
                }
            }
        }
    }

    private func route(from origin: CLPlacemark, to destination: CLPlacemark,
                        completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(placemark: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(placemark: destination))
        request.transportType = .automobile
        request.departureDate = Date()

        MKDirections(request: request).calculate { response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let route = response?.routes.first else {
                completion(.failure(TrafficError.noRoute))
                return
            }
            completion(.success(route.expectedTravelTime))
        }
    }

    private func resolvePlacemark(for address: String, completion: @escaping (Result<CLPlacemark, Error>) -> Void) {
        if let cached = placemarkCache[address] {
            completion(.success(cached))
            return
        }
        geocoder.geocodeAddressString(address) { [weak self] results, _ in
            guard let placemark = results?.first else {
                completion(.failure(TrafficError.geocodeFailed(address)))
                return
            }
            self?.placemarkCache[address] = placemark
            completion(.success(placemark))
        }
    }
}
