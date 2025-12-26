//
//  HoldToEndButton.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

//Views/Gameplay/Components/HoldToEndButton.swift
import SwiftUI
struct HoldToEndButton: View {
    var holdDuration: Double = 1.2
    var action: () -> Void

    @State private var isPressing = false
    @State private var pressFeedbackTrigger = false
    @State private var finishFeedbackTrigger = false
    @State private var timer: Task<Void, Never>?

    var body: some View {
        ZStack {
            Circle().fill(.thinMaterial)

            Circle()
                .trim(from: 0, to: isPressing ? 1 : 0)
                .stroke(.red.opacity(0.9),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
                .animation(.linear(duration: holdDuration), value: isPressing)

            Image(systemName: "stop.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.red)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(radius: 8, y: 3)
        .contentShape(Circle())

        // ✅ 用 DragGesture 精确拿到“按下/松开”
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    isPressing = true
                    pressFeedbackTrigger.toggle()

                    // 开始一个可取消的计时任务：按满才触发
                    timer?.cancel()
                    timer = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
                        // 如果这时仍在按住，触发
                        if isPressing {
                            finishFeedbackTrigger.toggle()
                            action()
                            isPressing = false
                        }
                    }
                }
                .onEnded { _ in
                    // 松手：取消计时并复位
                    timer?.cancel()
                    isPressing = false
                }
        )
//        .sensoryFeedback(.impact(weight: .light), trigger: pressFeedbackTrigger)
//        .sensoryFeedback(.impact(weight: .heavy), trigger: finishFeedbackTrigger)
        .accessibilityLabel("按住结束游戏")
    }
}


#Preview("HoldToEndButton Position Test") {
    ZStack {
        Color.gray.opacity(0.15).ignoresSafeArea()

        HoldToEndButton(holdDuration: 1.2) {}
            .padding(.trailing, 20)
            .padding(.bottom, 80)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottomTrailing
            )
    }
}

