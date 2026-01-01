//
//  RouteService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//

import MapKit
import CoreLocation

struct RouteService {
    func walkingRoute(to coordinate: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.transportType = .walking

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "RouteService", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有可用路线"])
        }
        return route
    }
}
