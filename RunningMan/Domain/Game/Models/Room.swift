//
//  Room.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//


import Foundation
import Supabase

struct Room: Codable, Identifiable, Hashable {
    let id: UUID
    var status: RoomStatus
    var rule: [String: AnyJSON]          // jsonb
    var regionId: UUID?
    var createdBy: UUID?
    var createdAt: Date

    // ✅ 新增：胜利方与结束时间（对应 rooms.winner / rooms.ended_at）
    var winner: String?
    var endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, rule
        case regionId = "region_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case winner
        case endedAt = "ended_at"
    }
}
