//
//  GameplayControlsView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

// Views/Gameplay/Components/GameplayControlsView.swift
import SwiftUI
import MapKit

struct GameplayControlsView: View {
    @Environment(GameManager.self) var game
    @Binding var isFollowingUser: Bool
    var onToggleCamera: () -> Void

    var body: some View {
        ZStack {
            // 底层：左右两端按钮
            HStack {
                // 左：视角按钮
                Button {
                    isFollowingUser.toggle()
                    onToggleCamera()
                } label: {
                    Image(systemName: isFollowingUser ? "location.fill" : "map")
                        .font(.title3)
                        .frame(width: 48, height: 48)                 // ✅ 更大
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .shadow(radius: 8, y: 3)
                }
                .buttonStyle(.plain)

                Spacer()

                // 右：结束按钮
                HoldToEndButton(holdDuration: 1.2) {
                    game.phase = .gameOver
                }
                .frame(width: 48, height: 48) // ✅ 更大（HoldToEndButton 里也建议改成 48）
            }

            // 顶层：居中的“停止导航”
            let showStop = (game.currentRoute != nil)

            Button {
                game.cancelNavigation()
            } label: {
                Label("停止导航", systemImage: "xmark.circle.fill")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.red.opacity(0.88))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(radius: 10, y: 4)
            .opacity(showStop ? 1 : 0)
            .scaleEffect(showStop ? 1 : 0.96)
            .allowsHitTesting(showStop)
            .animation(.easeInOut(duration: 0.18), value: showStop)

        }
        .animation(.easeInOut(duration: 0.18), value: game.currentRoute != nil)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
