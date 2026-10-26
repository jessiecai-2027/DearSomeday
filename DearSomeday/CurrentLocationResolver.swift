//
//  CurrentLocationResolver.swift
//  DearSomeday
//

import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class CurrentLocationResolver: NSObject, ObservableObject {

    @Published private(set) var isRequesting = false
    @Published private(set) var message: String?
    @Published private(set) var hasError = false

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentPlaceLabel() async -> String? {
        isRequesting = true
        message = nil
        hasError = false
        defer { isRequesting = false }

        guard CLLocationManager.locationServicesEnabled() else {
            fail(with: "Location Services are turned off.")
            return nil
        }

        let status = await authorizationStatus()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            fail(with: "Location permission is needed to use your current place.")
            return nil
        }

        do {
            let location = try await requestLocation()
            let placeLabel = try await reverseGeocode(location)
            message = "Added your current place."
            return placeLabel
        } catch {
            fail(with: "Couldn’t find your current place. You can still type it in.")
            return nil
        }
    }

    private func authorizationStatus() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return Self.coordinateLabel(for: location)
        }

        let mapItems = try await request.mapItems
        if let label = mapItems.first.flatMap(Self.label(for:)) {
            return label
        }

        return Self.coordinateLabel(for: location)
    }

    private func fail(with message: String) {
        self.message = message
        hasError = true
    }

    private static func label(for mapItem: MKMapItem) -> String? {
        [
            mapItem.addressRepresentations?.cityWithContext(.full),
            mapItem.addressRepresentations?.cityWithContext,
            mapItem.address?.shortAddress,
            mapItem.address?.fullAddress,
            mapItem.name
        ]
        .compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first { !$0.isEmpty }
    }

    private static func coordinateLabel(for location: CLLocation) -> String {
        let latitude = String(format: "%.4f", location.coordinate.latitude)
        let longitude = String(format: "%.4f", location.coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
}

extension CurrentLocationResolver: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            authorizationContinuation?.resume(returning: status)
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}
