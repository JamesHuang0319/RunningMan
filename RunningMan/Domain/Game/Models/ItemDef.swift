//
//  ItemDef.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/6.
//

// Game/Models/ItemDef.swift
import SwiftUI

enum RoleScope {
    case hunter
    case runner
}

enum ItemType: String, Codable, CaseIterable, Sendable {
    case mangoCloak = "mango_cloak"
    case bananaSlip = "banana_slip"
    case grapeRadar = "grape_radar"
    case watermelonMark = "watermelon_mark"
    case strawberryShield = "strawberry_shield"
}


struct ItemDef: Identifiable, Hashable, Sendable {
    var id: String { type.rawValue }

    let type: ItemType
    let icon: String
    let name: String
    let description: String
    let usageMessage: String
    let color: Color
    let cooldown: TimeInterval

    static let all: [ItemDef] = [
        .init(type: .mangoCloak, icon: "🥭", name: "芒果隐身",
              description: "30 秒内对敌方地图隐藏",
              usageMessage: "你已进入隐身状态（30秒）",
              color: .orange, cooldown: 60),

        .init(type: .bananaSlip, icon: "🍌", name: "香蕉滑倒",
              description: "命中猎人：5 秒内无法抓捕",
              usageMessage: "香蕉已出手！",
              color: .yellow, cooldown: 45),

        .init(type: .grapeRadar, icon: "🍇", name: "葡萄雷达",
              description: "扫描 120m 内敌人并提示",
              usageMessage: "雷达扫描中…",
              color: .purple, cooldown: 30),

        .init(type: .watermelonMark, icon: "🍉", name: "西瓜标记",
              description: "目标 12 秒暴露（强制高亮/无法隐身）",
              usageMessage: "目标已被标记！",
              color: .red, cooldown: 50),

        .init(type: .strawberryShield, icon: "🍓", name: "草莓护盾",
              description: "抵消 1 次抓捕",
              usageMessage: "护盾已激活（1次）",
              color: .pink, cooldown: 70),
    ]
}

extension ItemDef {
    static let byType: [ItemType: ItemDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.type, $0) })
}

extension ItemType {
    var roleScope: RoleScope {
        switch self {
        case .grapeRadar , .watermelonMark:
            return .hunter   // ✅ 改这里
        case .mangoCloak, .strawberryShield, .bananaSlip:
            return .runner
        }
    }
}
