//
//  GameRole.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//

import Foundation

enum GameRole: String, Codable, CaseIterable, Identifiable {
    case hunter
    case runner
    case spectator

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hunter: return "👻 鬼"
        case .runner: return "🏃 人"
        case .spectator: return "👀 观众"
        }
    }
}
