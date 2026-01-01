//
//  Extensions.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

// Extensions.swift
import CoreLocation
import MapKit

// 让经纬度支持 "==" 对比，解决 .onChange 报错
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return abs(lhs.latitude - rhs.latitude) < 0.000001 &&
               abs(lhs.longitude - rhs.longitude) < 0.000001
    }
}

