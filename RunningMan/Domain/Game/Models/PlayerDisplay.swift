//
//  Player.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//


import Foundation
import CoreLocation


// 核心玩家模型
struct PlayerDisplay: Identifiable, Equatable {
    let id: UUID                 // userId
    let roomId: UUID

    // Profile（低频）
    var displayName: String
    
    /// ✅ 1. 临时下载链接 (Supabase Signed URL)
    let avatarDownloadURL: URL?
    
    /// ✅ 2. 永久缓存 Key (Storage Path)
    let avatarCacheKey: String?
    
    // 游戏状态（来自 RoomPlayerState）
    var role: GameRole
    var status: PlayerStatus

    // 位置
    var coordinate: CLLocationCoordinate2D
    var lastSeenAt: Date?

    // 你地图上需要的标记
    var isMe: Bool = false
    var isOffline: Bool = false
    let isExposed: Bool // 是否因出圈而暴露
    
    // 用于地图显示的唯一标识
    static func == (lhs: PlayerDisplay, rhs: PlayerDisplay) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.status == rhs.status &&
        lhs.role == rhs.role &&
        lhs.isExposed == rhs.isExposed
    }

}
