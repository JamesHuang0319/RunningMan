//
//  GameOverView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI

struct GameOverView: View {
    @Environment(GameManager.self) var game

    var body: some View {
        VStack {
            Spacer()

            // 🎯 结算主卡片
            VStack(spacing: 16) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("游戏结束")
                    .font(.largeTitle.bold())

                Text("你可以再来一局，或者返回设置调整区域与角色。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider().opacity(0.4)

                // 📊 简单统计
                VStack(spacing: 10) {
                    statRow(title: "当前角色", value: game.currentUser.role.rawValue)
                    statRow(title: "游戏区域", value: game.selectedRegion.name)
                }
            }
            .glassCard(cornerRadius: 24)
            .padding(.horizontal, 24)

            Spacer()

            // 🎮 操作区
            VStack(spacing: 12) {

                // 主操作：再来一局
                Button {
                    game.endGame()
                    game.startGame()
                } label: {
                    Label("再来一局", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                // 次操作：返回设置
                Button {
                    game.backToSetup()
                } label: {
                    Text("返回设置")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Subviews

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}
