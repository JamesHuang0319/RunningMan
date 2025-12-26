//
//  PlayerAnnotationView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

// Views/Gameplay/Components/PlayerAnnotationView.swift
import SwiftUI
import CoreLocation

struct PlayerAnnotationView: View {
    let player: Player

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: player.role == .hunter ? "exclamationmark.shield.fill" : "figure.run")
                .font(.title2)
                .foregroundColor(.white)
                .padding(6)
                .background(player.role == .hunter ? .red : .green)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(.white, lineWidth: 2)
                )
                .shadow(radius: 3)
            
            // 小三角指示器
            Image(systemName: "triangle.fill")
                .font(.caption2)
                .foregroundColor(player.role == .hunter ? .red : .green)
                .offset(y: -3)
                .rotationEffect(.degrees(180))
                .shadow(radius: 1)
        }
    }
}

#Preview {
    PlayerAnnotationView(player: Player(id: UUID(), name: "测试", role: .hunter, status: .active, coordinate: .init()))
}
