//
//  ProfileRow.swift
//

import Foundation

/// 数据库表 profiles 的行
struct ProfileRow: Codable, Equatable, Identifiable {
    let id: UUID
    var username: String?
    var fullName: String?
    var avatarURL: String?
    
    // ✅ 新增统计字段
    var totalGames: Int?
    var totalWins: Int?
    var totalDistance: Double? // 单位：km

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        // ✅ 映射数据库字段
        case totalGames = "total_games"
        case totalWins = "total_wins"
        case totalDistance = "total_distance"
    }
}


