//
//  ProfileRow.swift
//

import Foundation

// Domain/Profile/Models/ProfileRow.swift

struct ProfileRow: Codable, Identifiable {
    let id: UUID
    var username: String?
    var fullName: String?
    var avatarURL: String?
    let totalGames: Int
    let totalWins: Int
    let totalDistance: Double
    
    // ✅  新增：用于接收联表查询的成就列表
    // 使用 Optional，因为有些查询可能不包含此字段
    // 🛠️ 修复 3: 将 let 改为 var，允许在 Store 中更新隐藏状态
    var userAchievements: [UserAchievementRow]?

    enum CodingKeys: String, CodingKey {
        case id, username
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case totalGames = "total_games"
        case totalWins = "total_wins"
        case totalDistance = "total_distance"
        case userAchievements = "user_achievements" // 对应 Supabase 的关联查询 Key
    }
}

