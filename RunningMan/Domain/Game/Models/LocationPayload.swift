//
//  LocationPayload.swift
//  RunningMan
//
//  Created by RunningMan Dev on 2026/01/05.
//

import Foundation

/// 用于 Realtime Broadcast 的高频位置同步包
/// ⚠️ 不经过数据库，只在 WebSocket 通道中传输
public struct LocationPayload: Codable, Sendable {
    public let userId: UUID
    public let lat: Double
    public let lng: Double
    public let heading: Double? // 玩家朝向 (0-360)，可选
    public let speed: Double?   // 速度，可选
}
