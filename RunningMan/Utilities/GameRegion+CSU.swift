//
//  GameRegion+CSU.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//

import CoreLocation

extension GameRegion {

    // ⚠️ 关键修改：为每个区域手动指定固定的 UUID (uuidString)
    // 这样房主上传到数据库的 ID，其他玩家本地也能匹配上
    
    /// 方便计算距离的 CLLocation 包装
    /// 可在任何需要 CLLocation 的地方直接使用（如距离排序、安全区判断、地图中心等）
    var centerLocation: CLLocation {
        CLLocation(latitude: center.latitude, longitude: center.longitude)
    }

    static let csuMainCampus = GameRegion(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,  // ✅ 固定 ID
        name: "中南大学校本部",
        center: CLLocationCoordinate2D(latitude: 28.1706, longitude: 112.9253),
        initialRadius: 1000
    )

    static let csuSouthCampus = GameRegion(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,  // ✅ 固定 ID
        name: "中南大学南校区",
        center: CLLocationCoordinate2D(latitude: 28.1668, longitude: 112.9258),
        initialRadius: 900
    )

    static let csuNewCampus = GameRegion(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,  // ✅ 固定 ID
        name: "中南大学新校区",
        center: CLLocationCoordinate2D(latitude: 28.1663, longitude: 112.9368),
        initialRadius: 1000
    )

    static let csuRailwayCampus = GameRegion(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,  // ✅ 固定 ID
        name: "中南大学铁道校区",
        center: CLLocationCoordinate2D(latitude: 28.1948, longitude: 112.9910),
        initialRadius: 900
    )

    static let csuXiangyaNew = GameRegion(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,  // ✅ 固定 ID
        name: "湘雅医学院新校区",
        center: CLLocationCoordinate2D(latitude: 28.2288, longitude: 112.9621),
        initialRadius: 900
    )

    static let csuXiangyaOld = GameRegion(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,  // ✅ 固定 ID
        name: "湘雅医学院老校区",
        center: CLLocationCoordinate2D(latitude: 28.2496, longitude: 112.9808),
        initialRadius: 800
    )

    static let allCSURegions: [GameRegion] = [
        csuNewCampus,
        csuMainCampus,
        csuSouthCampus,
        csuRailwayCampus,
        csuXiangyaNew,
        csuXiangyaOld,
    ]
}
