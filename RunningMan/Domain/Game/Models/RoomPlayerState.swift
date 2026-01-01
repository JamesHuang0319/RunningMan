//
//  RoomPlayerState.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//
//  这是“唯一真相模型”：来自 Supabase room_players（Realtime 就订阅它）
//

import Foundation
import CoreLocation

/// room_players 表：建议主键 (room_id, user_id)
/// ✅ 低频：role/status
/// ✅ 高频：lat/lng/updated_at（最新位置）
/// ✅ joined_at / updated_at 用于“在线/离线/超时”
struct RoomPlayerState: Codable, Identifiable, Hashable {
    // 你 UI 常用 userId 当 id
    var id: UUID { userId }

    let roomId: UUID
    let userId: UUID

    var role: GameRole
    var status: PlayerStatus

    // 最新位置（Realtime 更新）
    var lat: Double?
    var lng: Double?

    // 用于“最后活跃时间/离线判断”
    var joinedAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case userId = "user_id"
        case role
        case status
        case lat
        case lng
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// 例：10 秒没更新就算“可能离线”（你可调）
    func isStale(now: Date = Date(), threshold: TimeInterval = 10) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > threshold
    }
}
