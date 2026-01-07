//
//  RoomEvent.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/6.
//

import Foundation
import Supabase

struct RoomEvent: Codable, Identifiable, Hashable {
    let id: Int64           // ✅ bigint -> Int64
    let roomId: UUID
    let type: String
    let actor: UUID?
    let target: UUID?
    let payload: JSONObject?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case type, actor, target, payload
        case createdAt = "created_at"
    }

    func payloadString(_ key: String) -> String? { payload?[key]?.stringValue }
    func payloadInt(_ key: String) -> Int? { payload?[key]?.intValue }
    func payloadDouble(_ key: String) -> Double? { payload?[key]?.doubleValue }
    func payloadBool(_ key: String) -> Bool? { payload?[key]?.boolValue }
    func payloadObject(_ key: String) -> JSONObject? { payload?[key]?.objectValue }
}
