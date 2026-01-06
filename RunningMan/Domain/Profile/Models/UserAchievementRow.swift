//
//  UserAchievementRow.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/3.
//

import Foundation

// ✅ 新增：数据库成就行模型
// Domain/Profile/Models/UserAchievementRow.swift
struct UserAchievementRow: Codable, Identifiable {
    let id: Int
    let type: String
    let createdAt: Date
    var isHidden: Bool // ✅ 新增

    enum CodingKeys: String, CodingKey {
        case id, type
        case createdAt = "created_at"
        case isHidden = "is_hidden" // ✅ 映射数据库字段
    }
}
