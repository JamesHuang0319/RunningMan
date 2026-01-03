//
//  UserAchievementRow.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/3.
//

import Foundation

// ✅ 新增：数据库成就行模型
struct UserAchievementRow: Codable, Identifiable {
    let id: Int
    let userId: UUID
    let type: String // 对应 AchievementItem 的类型
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
    }
}

