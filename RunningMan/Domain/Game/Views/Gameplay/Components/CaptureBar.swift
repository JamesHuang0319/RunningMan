//
//  CaptureBar.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/8.
//

import SwiftUI

struct CaptureBar: View {
    // --- 外部传入属性 ---
    let state: MainMapView.CaptureState
    let targetName: String
    let dist: Double
    let onHold: () -> Void
    let onTapLock: () -> Void

    // --- 内部 UI 状态 ---
    @State private var holdProgress: CGFloat = 0
    @State private var isPressing = false
    
    // 判定逻辑 (根据距离切换紫色/蓝色的视觉反馈)
    private var isWithinRange: Bool { dist <= 15 }
    
    // 长按触发时间 (1.5秒增加操作的确认感)
    private let totalHoldDuration: Double = 1.5

    // 主题色切换
    private var themeColor: Color {
        isWithinRange ? .purple : .blue
    }

    var body: some View {
        // 全局容器：220x74 胶囊
        ZStack {
            // 1. 底层：毛玻璃背景
            Capsule()
                .fill(.ultraThinMaterial)
                .frame(width: 220, height: 74)
                .shadow(color: themeColor.opacity(isWithinRange ? 0.4 : 0.1),
                        radius: 12, y: 8)
            
            // 2. 进度层：确保填充不跑出格
            ZStack(alignment: .leading) {
                // 进度填充色块
                Rectangle()
                    .fill(themeColor.opacity(0.25))
                    .frame(width: 220 * holdProgress, height: 74)
            }
            .frame(width: 220, height: 74)
            .clipShape(Capsule()) // ✅ 关键：强制裁剪，确保进度条圆角不溢出
            
            // 3. 内容层：图标 + 文字（整体居中排列）
            HStack(spacing: 12) {
                // 图标圆圈
                ZStack {
                    Circle()
                        .fill(themeColor.gradient)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: state == .locked ? "target" : (isWithinRange ? "bolt.fill" : "antenna.radiowaves.left.and.right"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        // iOS 17 动画效果
                        .symbolEffect(.bounce, options: .repeat(2), value: isWithinRange)
                        .symbolEffect(.variableColor.iterative, options: .repeating, value: isPressing)
                }
                
                // 文本信息 (保持靠左对齐，但 VStack 本身在胶囊中居中)
                VStack(alignment: .leading, spacing: 0) {
                    Text("抓捕 \(targetName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(dist))")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundStyle(themeColor)
                        
                        Text("M")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(themeColor.opacity(0.7))
                        
                        Text("• \(isWithinRange ? "就绪" : "追踪")")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            // ✅ 不加 Spacer()，让 HStack 根据内容宽度在父容器(220宽)中自动居中
            
            // 4. 顶层：动态边框与发光
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [themeColor.opacity(0.8), themeColor.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: isWithinRange ? 2.5 : 1.2
                )
                .frame(width: 220, height: 74)
                .overlay {
                    if isWithinRange {
                        Capsule()
                            .stroke(themeColor.opacity(0.3), lineWidth: 4)
                            .blur(radius: 6)
                    }
                }
        }
        .frame(width: 220, height: 74) // 明确组件物理尺寸
        // --- 交互动效与手势 ---
        .scaleEffect(isPressing ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressing)
        .onTapGesture {
            onTapLock()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing {
                        isPressing = true
                        startHoldLogic()
                    }
                }
                .onEnded { _ in
                    cancelHoldLogic()
                }
        )
    }

    // MARK: - 手势逻辑
    
    private func startHoldLogic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // 进度填充动画
        withAnimation(.linear(duration: totalHoldDuration)) {
            holdProgress = 1.0
        }
        
        // 延迟检查是否仍在按压
        DispatchQueue.main.asyncAfter(deadline: .now() + totalHoldDuration) {
            if isPressing {
                onHold() // 触发业务逻辑（撕名牌UI）
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                cancelHoldLogic()
            }
        }
    }

    private func cancelHoldLogic() {
        isPressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        // 模拟地图背景
        Color.gray.opacity(0.8).ignoresSafeArea()
        
        VStack(spacing: 50) {
            Text("CaptureBar 预览")
                .font(.headline)
                .foregroundStyle(.white)
            
            // 状态 1：远程追踪（蓝色）
            CaptureBar(
                state: .idle,
                targetName: "八级大狂风",
                dist: 117,
                onHold: { print("Hold Complete") },
                onTapLock: { print("Tapped") }
            )
            
            // 状态 2：近距离就绪（紫色发光）
            CaptureBar(
                state: .locked,
                targetName: "小明",
                dist: 4,
                onHold: { print("Hold Complete") },
                onTapLock: { print("Tapped") }
            )
        }
    }
}
