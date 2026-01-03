//
//  AchievementDefinition.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/3.
//

struct AchievementDefinition: Codable {
    let type: String
    let name: String
    let description: String?
    let iconName: String
    let colorHex: String
    
    enum CodingKeys: String, CodingKey {
        case type, name, description
        case iconName = "icon_name"
        case colorHex = "color_hex"
    }
}
