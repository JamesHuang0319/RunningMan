//
//  PlayerModel.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/9.
//

import Foundation
import CoreLocation

// 游戏角色
enum GameRole: String, Codable, CaseIterable {
    case hunter = "👻 鬼"
    case runner = "🏃 人"
    case spectator = "👀 观众"
}

// 玩家状态
enum PlayerStatus: String, Codable {
    case active = "游戏中"
    case caught = "被抓了"
    case offline = "离线"
}

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
