//
//  GameConfig.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import CoreLocation

struct GameRegion: Identifiable, Hashable {
    let id: UUID
    let name: String

    /// 用于游戏缩圈中心（你可以先用估算值，后面再精修）
    let center: CLLocationCoordinate2D
    let initialRadius: Double

    /// 可选：校区边界（多边形）
    let boundary: [CLLocationCoordinate2D]

    /// 可选：推荐开局点（比如“南大门/图书馆/操场”）
    let startPoints: [CLLocationCoordinate2D]

    init(
        id: UUID = UUID(),
        name: String,
        center: CLLocationCoordinate2D,
        initialRadius: Double,
        boundary: [CLLocationCoordinate2D] = [],
        startPoints: [CLLocationCoordinate2D] = []
    ) {
        self.id = id
        self.name = name
        self.center = center
        self.initialRadius = initialRadius
        self.boundary = boundary
        self.startPoints = startPoints
    }

    static func == (lhs: GameRegion, rhs: GameRegion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}



// 缩圈的状态
struct SafeZone {
    var center: CLLocationCoordinate2D
    var radius: Double
    var isShrinking: Bool = false
}
