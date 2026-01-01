//
//  RoomStatus.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/29.
//


enum RoomStatus: String, Codable, CaseIterable {
    case waiting = "waiting"
    case playing = "playing"
    case ended = "ended"
    case closed = "closed"
}
