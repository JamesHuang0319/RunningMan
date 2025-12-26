//
//  GameHUDView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

// Views/Gameplay/Components/GameHUDView.swift
import SwiftUI

struct GameHUDView: View {
    @Environment(GameManager.self) var game

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("缩圈中…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("安全区半径: \(Int(game.safeZone?.radius ?? 0))m")
                    .font(.headline)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: game.safeZone?.radius ?? 0)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                // 角色胶囊
                Text(game.currentUser.role.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))

                Text(game.selectedRegion.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .glassCard(cornerRadius: 18)
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}
