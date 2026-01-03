//
//  CaptureOverlayView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/31.
//

import SwiftUI

struct CaptureOverlayView: View {
    /// 核心重构：基于“角色+动作”的状态定义
    enum AnimationType {
        // --- 1. 游戏进行中 (Action) ---
        case hunterCaughtOne    // 猎人：抓捕成功 (橙色 - CAPTURED)
        
        // --- 2. 个人状态 (Personal) ---
        case runnerBusted       // 逃跑者：我被抓了 (红色 - BUSTED)
        
        // --- 3. 全局结算 (Game Over) ---
        case gameVictory        // 胜利：猎人抓完  (金色 - VICTORY)
        case gameDefeat         // 失败：猎人超时 / 逃跑者全灭 (灰色 - DEFEAT)
        case runnerEscaped      // 逃跑者：逃脱成功 (绿色 - ESCAPED，用于替代 Victory 的另一种风味)
    }

    let type: AnimationType
    let message: String
    var onDismiss: () -> Void

    // 动画状态
    @State private var scale: CGFloat = 2.5
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = -15
    @State private var flashOpacity: Double = 0.0
    @State private var textBlur: CGFloat = 10.0

    var body: some View {
        ZStack {
            // 1. 背景层
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorScheme(.dark) // 强制暗黑玻璃
                .ignoresSafeArea()

            // 叠加颜色氛围
            backgroundColor.ignoresSafeArea()

            // 2. 核心内容层
            VStack(spacing: 24) {
                // 印章主体
                ZStack {
                    // 光晕
                    stampView
                        .blur(radius: 20)
                        .opacity(isFancy ? 0.8 : 0.5)

                    // 实体
                    stampView
                }
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                .opacity(opacity)
                .blur(radius: textBlur)

                // 数据面板
                VStack(spacing: 8) {
                    // 装饰线
                    HStack {
                        Circle().frame(width: 6, height: 6)
                        Rectangle().frame(height: 1)
                        Circle().frame(width: 6, height: 6)
                    }
                    .foregroundStyle(themeColor.opacity(0.6))
                    .frame(width: 200)

                    Text(message)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .shadow(color: .black, radius: 2, x: 0, y: 1)
                }
                .opacity(opacity)
                .offset(y: opacity == 1 ? 0 : 20)
            }
        }
        // 3. 撞击闪光
        .overlay {
            Color.white.ignoresSafeArea().opacity(flashOpacity)
        }
        .onAppear {
            animateEntry()
        }
    }
    
    // MARK: - 逻辑分发
    
    // 是否使用华丽样式 (双层边框+星星)
    var isFancy: Bool {
        switch type {
        case .gameVictory, .gameDefeat, .runnerEscaped: return true
        default: return false
        }
    }
    
    var themeColor: Color {
        switch type {
        case .hunterCaughtOne: return Color(hex: "FF9500") // 战术橙
        case .runnerBusted:    return Color(hex: "FF3B30") // 警告红
        case .gameVictory:     return Color(hex: "FFD700") // 冠军金
        case .runnerEscaped:   return Color(hex: "32D74B") // 安全绿
        case .gameDefeat:      return Color.gray           // 失败灰
        }
    }
    
    var titleText: String {
        switch type {
        case .hunterCaughtOne: return "CAPTURED"
        case .runnerBusted:    return "BUSTED"
        case .gameVictory:     return "VICTORY"
        case .runnerEscaped:   return "ESCAPED"
        case .gameDefeat:      return "DEFEAT"
        }
    }
    
    var backgroundColor: Color {
        switch type {
        case .gameVictory:
            return Color.yellow.opacity(0.15)
        case .runnerEscaped:
            return Color.green.opacity(0.15)
        case .runnerBusted, .gameDefeat:
            return Color.red.opacity(0.1)
        case .hunterCaughtOne:
            return Color.black.opacity(0.3)
        }
    }
    
    // MARK: - 组件构建
    @ViewBuilder
    var stampView: some View {
        if isFancy {
            VictoryStampShape(text: titleText, color: themeColor)
        } else {
            StampShape(text: titleText, color: themeColor)
        }
    }

    // MARK: - 动画实现 (保持不变)
    private func animateEntry() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.prepare()
        impact.impactOccurred(intensity: 1.0)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.45, blendDuration: 0)) {
            scale = 1.0
            opacity = 1.0
            rotation = -5
            textBlur = 0
        }

        withAnimation(.easeOut(duration: 0.15)) { flashOpacity = 0.3 }
        withAnimation(.easeOut(duration: 0.3).delay(0.15)) { flashOpacity = 0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 0
                scale = 0.8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
        }
    }
}

// MARK: - 印章组件 (复用之前的)
struct StampShape: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 48, weight: .black, design: .rounded))
            .kerning(2)
            .foregroundStyle(color)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color, lineWidth: 6))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.6), lineWidth: 2).padding(5))
            .compositingGroup()
            .rotationEffect(.degrees(-2))
    }
}

struct VictoryStampShape: View {
    let text: String
    let color: Color
    var body: some View {
        ZStack {
            Text(text)
                .font(.system(size: 56, weight: .heavy, design: .serif))
                .kerning(6)
                .foregroundStyle(LinearGradient(colors: [color, .white, color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: color.opacity(0.5), radius: 10)
                .padding(.horizontal, 50)
                .padding(.vertical, 24)
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient(colors: [color.opacity(0.2), color, color.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 4)
                        RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6])).padding(6)
                    }
                )
            VStack {
                HStack { Star(); Spacer(); Star() }
                Spacer()
                HStack { Star(); Spacer(); Star() }
            }
            .padding(4)
            .foregroundStyle(color)
        }
        .fixedSize()
    }
    @ViewBuilder func Star() -> some View {
        Image(systemName: "star.fill").font(.system(size: 16)).shadow(color: color, radius: 4)
    }
}

// MARK: - Previews (修复 escaped 报错)
#Preview("Runner Escaped") {
    ZStack { Color.black.ignoresSafeArea(); CaptureOverlayView(type: .runnerEscaped, message: "存活时间达标") {} }
}
#Preview("Hunter Caught One") {
    ZStack { Color.gray.ignoresSafeArea(); CaptureOverlayView(type: .hunterCaughtOne, message: "距离: 5m") {} }
}
