//
//  PlayerStatus.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//


import Foundation


enum PlayerStatus: String, Codable, CaseIterable, Identifiable, Equatable {

    case ready      // 大厅准备
    case active     // 游戏中
    case caught     // 被抓（失败）
    case finished   // ✅ 主动结束本局参与（不等于被抓）
    
    case offline    // ⚠️ UI 派生状态（不写 DB）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ready:    return "已准备"
        case .active:   return "游戏中"
        case .caught:   return "被抓捕"
        case .finished: return "已结束行动"
        case .offline:  return "离线"
        }
    }
}

extension PlayerStatus {

    /// ✅ 允许写入 DB 的玩法状态
    var isDBPlayableStatus: Bool {
        switch self {
        case .ready, .active, .caught, .finished:
            return true
        case .offline:
            return false
        }
    }
}
