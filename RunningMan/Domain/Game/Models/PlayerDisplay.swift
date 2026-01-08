//
//  Player.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//


import Foundation
import CoreLocation
import Supabase


// UI使用的核心玩家模型
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
    var state: JSONObject?   // ✅ 直接带上 json（不要求改成 Codable）
    
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
extension PlayerDisplay {
    var stateView: PlayerStateView { PlayerStateView(state) }
}


struct PlayerStateView: Equatable {
    let raw: JSONObject

    init(_ raw: JSONObject?) {
        self.raw = raw ?? [:]
    }

    var cloakUntil: Date? { raw.date("cloak_until") }
    var revealUntil: Date? { raw.date("reveal_until") }
    var slipUntil: Date? { raw.date("slip_until") }
    var shieldCharges: Int { raw.int("shield_charges") ?? 0 }

    func isCloaked(now: Date = Date()) -> Bool {
        guard let t = cloakUntil else { return false }
        return now < t
    }

    func isRevealed(now: Date = Date()) -> Bool {
        guard let t = revealUntil else { return false }
        return now < t
    }

    func isSlipped(now: Date = Date()) -> Bool {
        guard let t = slipUntil else { return false }
        return now < t
    }

    func remainSeconds(_ date: Date?, now: Date = Date()) -> Int? {
        guard let t = date else { return nil }
        let s = Int(ceil(t.timeIntervalSince(now)))
        return s > 0 ? s : nil
    }

    var cloakRemain: Int? { remainSeconds(cloakUntil) }
    var revealRemain: Int? { remainSeconds(revealUntil) }
    var slipRemain: Int? { remainSeconds(slipUntil) }
}
