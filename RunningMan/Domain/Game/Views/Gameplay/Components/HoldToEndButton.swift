//
//  HoldToEndButton.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI

struct HoldToEndButton: View {
    var holdDuration: Double = 1.5
    var action: () async -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var timerTask: Task<Void, Never>?

    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactLight = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            // 1. 核心玻璃底盘
            Circle()
                .fill(.ultraThinMaterial) // 保持苹果原生的毛玻璃效果
                .overlay(
                    // 模拟玻璃边缘的高光 (非常关键)
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                // 仅保留一个非常轻微的自然阴影
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            
            // 2. 点击时的“高亮”层 (替代之前的红色光晕)
            // 当按下时，玻璃会变亮一点，产生物理反馈感
            Circle()
                .fill(isPressing ? Color.white.opacity(0.2) : Color.clear)
                .animation(.easeInOut(duration: 0.2), value: isPressing)

            // 3. 进度条背景轨道 (半透明灰色，极细，增加精致感)
            Circle()
                .stroke(Color.primary.opacity(0.03), lineWidth: 3)
                .frame(width: 52, height: 52)

            // 4. 长按进度环 (亮红色，带有微弱的外发光)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))
                // 线性增长确保平滑
                .animation(.linear(duration: isPressing ? holdDuration : 0.2), value: progress)
                // 给进度条一点点红色的投影，增加“通电”感
                .shadow(color: isPressing ? .red.opacity(0.3) : .clear, radius: 4)

            // 5. 停止图标
            // 颜色：平时深灰/黑，按下变亮红
            Image(systemName: "stop.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isPressing ? Color.red : Color.primary.opacity(0.75))
                // 补偿性缩放：当外框变小时，图标轻微变大
                .scaleEffect(isPressing ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressing)
        }
        .frame(width: 64, height: 64)
        // 整体按下缩放：从 1.0 缩到 0.96，不要缩太多以免显得局促
        .scaleEffect(isPressing ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressing)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let distance = sqrt(pow(value.location.x - 32, 2) + pow(value.location.y - 32, 2))
                    if distance > 45 { // 稍微收紧有效范围
                        if isPressing { cancelPress() }
                    } else {
                        if !isPressing { startPress() }
                    }
                }
                .onEnded { _ in
                    cancelPress()
                }
        )
    }

    private func startPress() {
        guard !isPressing else { return }
        isPressing = true
        progress = 1.0
        impactLight.impactOccurred()

        timerTask?.cancel()
        timerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            if isPressing {
                finishPress()
            }
        }
    }

    private func cancelPress() {
        timerTask?.cancel()
        timerTask = nil
        isPressing = false
        progress = 0
    }

    private func finishPress() {
        timerTask?.cancel()
        timerTask = nil
        impactHeavy.impactOccurred()
        isPressing = false
        progress = 0
        Task { await action() }
    }
}

// MARK: - Previews
#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        HoldToEndButton(holdDuration: 1.5) {
            print("Action Triggered!")
        }
    }
}
