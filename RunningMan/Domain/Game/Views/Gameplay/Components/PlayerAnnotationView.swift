//
//  PlayerAnnotationView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//


import SwiftUI
import Kingfisher

struct PlayerAnnotationView: View {
    let player: PlayerDisplay
    let distance: Double
    
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 4) {
            
            // --- ⚠️ 毒圈暴露标记（头顶）---
            // 如果暴露了，在所有图标之上显示感叹号
            if player.isExposed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolEffect(.pulse)
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(Circle().fill(.black.opacity(0.8)))
                    .offset(y: -35)
                    .zIndex(10) // 确保在最上层
            }
            
            // --- 🎯 核心图标层 ---
            ZStack {
                // <10m：显示撕名牌大按钮，完全取代头像
                if distance < 10 && player.role == .runner && !player.isMe {
                    CaptureButtonView()
                } else {
                    // 常规模式（含 <20m 预警光环）
                    NormalAvatarView()
                }
                
                // 被抓状态角标（任何模式都显示）
                if player.status == .caught {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black)
                        .font(.title3)
                        .offset(x: 16, y: -16)
                        .zIndex(20) // 确保在最上层
                }
            }
            .scaleEffect(player.isMe ? 1.1 : 1.0)
            
            // --- 名字或距离标签 ---
            Text(distance < 10 && !player.isMe ? "\(Int(distance))m" : player.displayName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(distance < 10 && !player.isMe ? .red : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(roleColor.opacity(0.8), in: Capsule())
                .shadow(radius: 2)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.coordinate)
    }
    
    // MARK: - 撕名牌专用大按钮
    @ViewBuilder
    private func CaptureButtonView() -> some View {
        ZStack {
            // 外层扩散波纹 (双层交替，视觉冲击更强)
            Circle()
                .stroke(Color.red.opacity(0.6), lineWidth: 5)
                .frame(width: 90, height: 90)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0 : 1)
            
            Circle()
                .stroke(Color.red.opacity(0.4), lineWidth: 5)
                .frame(width: 90, height: 90)
                .scaleEffect(isPulsing ? 1.0 : 1.6)
                .opacity(isPulsing ? 1 : 0)
                .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.3), value: isPulsing)
            
            // 核心按钮 (更大 + 内阴影)
            Circle()
                .fill(Color.red.gradient.shadow(.inner(color: .black.opacity(0.4), radius: 4)))
                .frame(width: 70, height: 70)
                .overlay(
                    Image(systemName: "hand.raised.fill")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                )
                .shadow(color: .red.opacity(0.8), radius: 15, y: 8)
                .scaleEffect(isPulsing ? 1.08 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    // MARK: - 常规头像视图 (含 <20m 预警)
    @ViewBuilder
    private func NormalAvatarView() -> some View {
        ZStack {
            // <20m 预警红光光环
            if distance < 20 && !player.isMe {
                Circle()
                    .stroke(Color.red.opacity(0.7), lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
                    .onAppear {
                        // 确保动画只绑定一次
                        if !isPulsing {
                            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                isPulsing = true
                            }
                        }
                    }
                    .onDisappear { isPulsing = false }
            }
            
            // 头像底圈
            Circle()
                .fill(roleColor)
                .frame(width: 44, height: 44)
                .shadow(color: roleColor.opacity(0.5), radius: 6, y: 3)
            
            // 头像图片
            if let url = player.avatarDownloadURL, let cacheKey = player.avatarCacheKey {
                KFImage(source: .network(Kingfisher.ImageResource(downloadURL: url, cacheKey: cacheKey)))
                    .placeholder { ProgressView().tint(.white) }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            } else {
                Image(systemName: roleIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
    
    // MARK: - Helpers
    private var roleColor: Color {
        if player.status == .caught { return .gray }
        switch player.role {
        case .runner: return .blue
        case .hunter: return .red
        case .spectator: return .purple
        }
    }
    
    private var roleIcon: String {
        switch player.role {
        case .runner: return "figure.run"
        case .hunter: return "eye.fill"
        case .spectator: return "camera.fill"
        }
    }
}
