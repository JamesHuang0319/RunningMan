//
//  ProfileRow.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/24.
//


import Foundation

/// 数据库表 profiles 的行
struct ProfileRow: Codable, Equatable, Identifiable {
    let id: UUID
    var username: String?
    var fullName: String?
    var avatarURL: String?   // storage path: "<uid>/avatar.jpg"

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}
