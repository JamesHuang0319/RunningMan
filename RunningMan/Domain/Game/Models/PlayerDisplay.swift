//
//  Player.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//


import Foundation
import CoreLocation


// 核心玩家模型
struct Player: Identifiable, Equatable {
    let id: UUID
    var name: String
    var role: GameRole
    var status: PlayerStatus
    var coordinate: CLLocationCoordinate2D
    
    // 用于地图显示的唯一标识
    static func == (lhs: Player, rhs: Player) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.status == rhs.status &&
        lhs.role == rhs.role
    }

}
