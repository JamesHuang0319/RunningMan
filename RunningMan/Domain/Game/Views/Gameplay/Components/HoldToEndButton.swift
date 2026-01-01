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
            // 底层：统一 64*64 的浮层按钮底盘（干净）
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            // 长按进度环：按住才显示（不抢戏）
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.red,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(isPressing ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isPressing)

            // 图标：常态中性，按住变红
            Image(systemName: isPressing ? "stop.circle.fill" : "stop.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(isPressing ? Color.red : Color.primary.opacity(0.85))
                .animation(.easeOut(duration: 0.12), value: isPressing)
        }
        .frame(width: 64, height: 64)               // ✅ 固定 64*64
        .scaleEffect(isPressing ? 0.96 : 1.0)       // 按下轻微缩放
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isPressing)
        .contentShape(Circle())
        .onAppear {
            impactHeavy.prepare()
            impactLight.prepare()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing { startPress() }
                }
                .onEnded { _ in
                    cancelPress()
                }
        )
        .accessibilityLabel("结束跑步")
        .accessibilityHint("长按确认结束")
    }

    private func startPress() {
        isPressing = true
        progress = 0
        impactLight.impactOccurred()

        timerTask?.cancel()
        timerTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                let p = min(1, t / holdDuration)
                progress = CGFloat(p)

                if p >= 1 {
                    finishPress()
                    break
                }
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
            }
        }
    }

    private func cancelPress() {
        timerTask?.cancel()
        timerTask = nil
        isPressing = false
        withAnimation(.easeOut(duration: 0.15)) {
            progress = 0
        }
    }

    private func finishPress() {
        timerTask?.cancel()
        timerTask = nil
        isPressing = false
        progress = 0
        impactHeavy.impactOccurred()
        Task { await action() }
    }
}
