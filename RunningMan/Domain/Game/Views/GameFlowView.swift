//
//  GameFlowView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI

struct GameFlowView: View {
    @Environment(GameStore.self) var game

    var body: some View {
        NavigationStack {
            Group {
                switch game.phase {
                case .setup:
                    EntranceView() // 改名：入口视图
                    .transition(.opacity)
                case .lobby:
                    LobbyView()
                case .playing:
                    MainMapView()
                case .gameOver:
                    GameOverView()
                }
            }
        }
    }
}
