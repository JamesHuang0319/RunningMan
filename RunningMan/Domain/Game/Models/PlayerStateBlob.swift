//
//  PlayerStateBlob.swift
//  RunningMan
//
//  room_players.state: jsonb 的结构定义（客户端/服务端共识）
//

import Foundation
import Supabase
/// 约定：room_players.state 的顶层结构
/// - 道具相关：items/cooldowns/effects
/// - 其他将来扩展：flags / debug / metrics ...
struct PlayerStateBlob: Codable, Hashable, Sendable {

    /// 背包/道具库存：每种道具剩余次数
    var items: [String: Int] = [:]
    /// 冷却表：itemType -> 冷却到期时间（ISO8601字符串）
    var cooldowns: [String: String] = [:]
    /// 临时效果：effectType -> Effect
    var effects: [String: Effect] = [:]

    /// 任意扩展字段（以后你想加“阵营天赋/局内成就/统计”都放这里）
    var flags: [String: Bool]? = nil
    var debug: [String: String]? = nil

    // MARK: - Nested

    struct Effect: Codable, Hashable, Sendable {
        /// 哪个道具/来源触发的（可选）
        var source: String? = nil
        /// 效果到期时间（ISO8601）
        var until: String
        /// 效果强度/参数（例如雷达半径、护盾次数等）
        var value: Double? = nil
        /// 次数类效果（例如护盾可抵消 1 次抓捕）
        var stacks: Int? = nil
    }
}


extension RoomPlayerState {

    /// 把 jsonb state 解成强类型 blob（失败则返回空结构）
    func decodedBlob() -> PlayerStateBlob {
        guard let state else { return PlayerStateBlob() }

        let dict: [String: Any] = state.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(dict) else {
            return PlayerStateBlob()
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            return try JSONDecoder().decode(PlayerStateBlob.self, from: data)
        } catch {
            return PlayerStateBlob()
        }
    }

    func itemCount(_ itemType: String) -> Int {
        decodedBlob().items[itemType] ?? 0
    }

    func isInCooldown(_ itemType: String, now: Date = Date()) -> Bool {
        let blob = decodedBlob()
        guard let s = blob.cooldowns[itemType],
              let until = ISO8601DateFormatter().date(from: s)
        else { return false }
        return now < until
    }

    func hasActiveEffect(_ effectKey: String, now: Date = Date()) -> Bool {
        let blob = decodedBlob()
        guard let e = blob.effects[effectKey],
              let until = ISO8601DateFormatter().date(from: e.until)
        else { return false }
        return now < until
    }
}
