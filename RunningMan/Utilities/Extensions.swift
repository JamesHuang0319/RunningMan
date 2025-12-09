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

// 中南大学 所有校区位置
extension GameRegion {
    static let csuMainCampus = GameRegion(
        name: "中南大学本部",
        // 这个坐标是根据 932 麓山南路（CSU 主校区地址）得到的近似值
        center: CLLocationCoordinate2D(latitude: 28.1706, longitude: 112.9253),
        initialRadius: 1000
    )

    static let csuSouthCampus = GameRegion(
        name: "中南大学南校区",
        // 这里先给近似值：你最好后面用高德/Apple 地图再微调
        center: CLLocationCoordinate2D(latitude: 28.1668, longitude: 112.9258),
        initialRadius: 900
    )

    static let csuNewCampus = GameRegion(
        name: "中南大学新校区",
        center: CLLocationCoordinate2D(latitude: 28.1663, longitude: 112.9368),
        initialRadius: 1000
    )

    static let csuRailwayCampus = GameRegion(
        name: "中南大学铁道校区",
        center: CLLocationCoordinate2D(latitude: 28.1948, longitude: 112.9910),
        initialRadius: 900
    )

    static let csuXiangyaNew = GameRegion(
        name: "湘雅医学院新校区",
        center: CLLocationCoordinate2D(latitude: 28.2288, longitude: 112.9621),
        initialRadius: 900
    )

    static let csuXiangyaOld = GameRegion(
        name: "湘雅医学院老校区",
        center: CLLocationCoordinate2D(latitude: 28.2496, longitude: 112.9808),
        initialRadius: 800
    )

    static let allRegions: [GameRegion] = [
        csuNewCampus,
        csuMainCampus,
        csuSouthCampus,
        csuRailwayCampus,
        csuXiangyaNew,
        csuXiangyaOld
    ]
}


// 模拟用户坐标
extension Player {
    static let mockCurrentUser = Player(
        id: UUID(),
        name: "我",
        role: .hunter,
        status: .active,
        coordinate: CLLocationCoordinate2D(latitude: 28.1663, longitude: 112.9368)
    )

    static let mockOthers: [Player] = [
        Player(
            id: UUID(),
            name: "小明 (逃亡者)",
            role: .runner,
            status: .active,
            coordinate: CLLocationCoordinate2D(latitude: 28.1670, longitude: 112.9380)
        ),
        Player(
            id: UUID(),
            name: "小红 (围观)",
            role: .spectator,
            status: .active,
            coordinate: CLLocationCoordinate2D(latitude: 28.1650, longitude: 112.9350)
        )
    ]
}

