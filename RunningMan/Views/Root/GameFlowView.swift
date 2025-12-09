//
//  GameFlowView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI

struct GameFlowView: View {
    @Environment(GameManager.self) var game

    var body: some View {
        NavigationStack {
            Group {
                switch game.phase {
                case .setup:
                    SetupView()
                case .playing:
                    MainMapView()
                case .gameOver:
                    GameOverView()
                }
            }
        }
    }
}
