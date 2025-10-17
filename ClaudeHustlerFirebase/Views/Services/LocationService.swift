// LocationService.swift - Enhanced with debugging
// Path: ClaudeHustlerFirebase/Views/Services/LocationService.swift

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
        checkInitialAuthorizationStatus()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
    }
    
    private func checkInitialAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
        // If already authorized, start updating immediately
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdatingLocation()
        }
    }
    
    // MARK: - Permission Handling
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        locationManager.startUpdatingLocation()
        
        // Request a single location update immediately
        locationManager.requestLocation()
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
@MainActor
extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        case .denied:
            locationError = "Location access denied. Please enable in Settings > Privacy > Location Services"
            
        case .restricted:
            locationError = "Location access restricted"
            
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        
        userLocation = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        locationError = error.localizedDescription
        
        // If it's a network error, we might still have a cached location
        if let location = manager.location {
            
            userLocation = location.coordinate
        }
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

// MARK: - CLAuthorizationStatus Debug Extension
extension CLAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Authorized Always"
        case .authorizedWhenInUse: return "Authorized When In Use"
        @unknown default: return "Unknown"
        }
    }
}
