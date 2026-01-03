//
//  AchievementItem.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/3.
//

import Foundation
import SwiftUI // ✅ 必须引入，才能使用 Color

// UI 使用的成就模型 (视图模型)
struct AchievementItem: Identifiable, Equatable {
    let id = UUID() // UI 唯一标识 (每次生成新的，仅供 ForEach 使用)
    
    // 数据库字段
    let dbID: Int?  // 对应 user_achievements.id (用于删除)
    let type: String // ✅ 新增：对应 achievement_definitions.type (用于反向查找配置)
    
    // UI 展示属性 (从 Definition 映射而来)
    let color: Color
    let icon: String
    let name: String
    
    // 提供一个便利构造器
    init(dbID: Int? = nil, type: String, color: Color, icon: String, name: String) {
        self.dbID = dbID
        self.type = type
        self.color = color
        self.icon = icon
        self.name = name
    }
    
    // 实现 Equatable (忽略 UUID)
    static func == (lhs: AchievementItem, rhs: AchievementItem) -> Bool {
        lhs.dbID == rhs.dbID &&
        lhs.type == rhs.type &&
        lhs.name == rhs.name
    }
}
