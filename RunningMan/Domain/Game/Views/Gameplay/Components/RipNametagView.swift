//
//  RipNametagView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/31.
//

import SwiftUI

struct RipNametagView: View {
    let targetName: String
    let onRip: () async -> Void
    let onCancel: () -> Void

    // 状态变量
    @State private var dragOffset: CGSize = .zero
    @State private var isRipped = false
    @State private var showParticles = false

    // 触感反馈生成器
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            // ✅ 这里只做 dim（不要再 background(.ultraThinMaterial) + 大黑底）
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { if !isRipped { onCancel() } }

            // ✅ 中心“玻璃面板”，像系统弹层
            VStack(spacing: 18) {
                header
                ripArea
                footer
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 22, y: 10)
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onAppear {
            impactLight.prepare()
            impactHeavy.prepare()
        }
    }

    // MARK: - UI Parts

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeating)

            Text("用力向下滑动撕下名牌！")
                .font(.system(.headline, design: .rounded).bold())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .opacity(isRipped ? 0 : 1)
        .animation(.easeOut(duration: 0.15), value: isRipped)
    }

    private var ripArea: some View {
        ZStack(alignment: .top) {
            baseSlot

            if !showParticles {
                NameTagCard(name: targetName)
                    .offset(y: dragOffset.height)
                    .rotationEffect(.degrees(Double(dragOffset.width) * 0.1))
                    .rotation3DEffect(
                        .degrees(Double(dragOffset.height) * 0.05),
                        axis: (x: 1, y: 0, z: 0)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged(handleDrag)
                            .onEnded(handleDragEnd)
                    )
                    .zIndex(10)
            }

            if showParticles {
                RipParticlesView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var baseSlot: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.black.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
            .frame(width: 240, height: 120)
    }

    private var footer: some View {
        Button {
            onCancel()
        } label: {
            Label("取消", systemImage: "xmark")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .opacity(isRipped ? 0 : 1)
        .animation(.easeOut(duration: 0.15), value: isRipped)
        .padding(.top, 6)
    }

    // MARK: - 逻辑处理（保留你的手感）

    private func handleDrag(_ val: DragGesture.Value) {
        guard !isRipped else { return }

        let yTranslation = max(0, val.translation.height)
        let resistance: CGFloat = 1.2
        let dampedY = yTranslation / resistance

        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: val.translation.width * 0.5, height: dampedY)
        }

        // 每隔一段距离轻震
        if Int(yTranslation) % 10 == 0 && yTranslation > 0 {
            let intensity = min(1.0, 0.5 + (yTranslation / 200.0))
            impactLight.impactOccurred(intensity: intensity)
        }
    }

    private func handleDragEnd(_ val: DragGesture.Value) {
        let threshold: CGFloat = 100

        if val.translation.height > threshold {
            performRip()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                dragOffset = .zero
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func performRip() {
        isRipped = true
        impactHeavy.impactOccurred(intensity: 1.0)

        withAnimation(.easeIn(duration: 0.15)) {
            dragOffset.height = 600
        }

        showParticles = true

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await onRip()
        }
    }
}

// MARK: - 子组件：名牌卡片（基本沿用你原版）
struct NameTagCard: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.20), radius: 6, y: 3)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(white: 0.9), lineWidth: 4)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 8)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)

                Spacer()

                Text(name)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)

                Spacer()
            }

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<15, id: \.self) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 3, height: 3)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(width: 240, height: 120)
    }
}

// MARK: - 粒子特效
struct RipParticlesView: View {
    @State private var time = 0.0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees(360 * now)

                for i in 0..<12 {
                    let rotation = Angle.degrees(Double(i) * 30) + angle
                    var c = context
                    c.translateBy(x: size.width / 2, y: size.height / 2)
                    c.rotate(by: rotation)
                    c.translateBy(x: 0, y: -80 - (time * 200))

                    let path = Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: 0, y: 20))
                    }
                    c.stroke(path, with: .color(.white), lineWidth: 3 * (1 - time))
                }
            }
            .opacity(1 - time)
        }
        .frame(width: 300, height: 300)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                time = 1.0
            }
        }
    }
}

#Preview("Rip Nametag (Light Modal)") {
    ZStack {
        Color.blue.opacity(0.2).ignoresSafeArea()
        RipNametagView(
            targetName: "RunningMan_007",
            onRip: { },
            onCancel: { }
        )
    }
}
