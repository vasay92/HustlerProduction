// LocationService.swift
// Path: ClaudeHustlerFirebase/Services/LocationService.swift

import Foundation
import CoreLocation
import MapKit

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // MARK: - Permission Handling
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - Geocoding
    func geocodeAddress(_ address: String) async throws -> CLLocationCoordinate2D {
        let placemarks = try await geocoder.geocodeAddressString(address)
        
        guard let location = placemarks.first?.location else {
            throw LocationError.geocodingFailed
        }
        
        return location.coordinate
    }
    
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        
        guard let placemark = placemarks.first else {
            throw LocationError.reverseGeocodingFailed
        }
        
        // Build a nice location string
        var components: [String] = []
        
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        
        return components.joined(separator: ", ")
    }
    
    // MARK: - Privacy Methods
    func obfuscateCoordinate(_ coordinate: CLLocationCoordinate2D, radiusInMeters: Double) -> CLLocationCoordinate2D {
        // Add random offset within the specified radius
        let r = radiusInMeters / 111300.0 // Convert meters to degrees (approximate)
        let randomAngle = Double.random(in: 0...(2 * .pi))
        let randomRadius = sqrt(Double.random(in: 0...1)) * r
        
        let lat = coordinate.latitude + randomRadius * cos(randomAngle)
        let lon = coordinate.longitude + randomRadius * sin(randomAngle)
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        case .denied, .restricted:
            locationError = "Location access denied. Please enable in Settings."
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
    }
}

// MARK: - Location Errors
enum LocationError: LocalizedError {
    case geocodingFailed
    case reverseGeocodingFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .geocodingFailed:
            return "Could not find location for this address"
        case .reverseGeocodingFailed:
            return "Could not determine address for this location"
        case .permissionDenied:
            return "Location permission denied"
        }
    }
}
