//
//  PlayerStatus.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//


import Foundation


enum PlayerStatus: String, Codable, CaseIterable, Identifiable, Equatable {
    case ready      // <--- 新增：在大厅里点了准备
    case active     // 游戏中（活着）
    case caught     // 被抓了 (或者叫 eliminated)
    case offline    // 离线 (可选，有时候离线是根据时间计算的，不一定是数据库状态)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ready: return "已准备"
        case .active: return "游戏中"
        case .caught: return "被抓捕"
        case .offline: return "离线"
        }
    }
}
