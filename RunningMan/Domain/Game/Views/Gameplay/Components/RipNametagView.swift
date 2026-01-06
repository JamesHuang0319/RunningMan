//
//  RipNametagView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/31.
//
import SwiftUI
import MapKit

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
            // 1. 背景层：高斯模糊 + 暗色遮罩
            Color.black.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击空白处也可以取消
                    if !isRipped { onCancel() }
                }
            
            VStack(spacing: 30) {
                Spacer()
                
                // 2. 提示文字：增加脉冲动画
                VStack(spacing: 8) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, options: .repeating) // iOS 17 动画
                    
                    Text("用力向下滑动撕下名牌！")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                }
                .opacity(isRipped ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: isRipped)
                
                // 3. 名牌核心交互区
                ZStack(alignment: .top) {
                    // --- 底座 (魔术贴毛面) ---
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.2), Color(white: 0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.5), lineWidth: 1)
                        )
                        .frame(width: 240, height: 120)
                        // 增加一种“空槽”的视觉感
                        .shadow(color: .white.opacity(0.1), radius: 1, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 4)
                    
                    // --- 名牌本体 (魔术贴钩面) ---
                    if !showParticles { // 撕下后瞬间隐藏实体，转为动画
                        NameTagCard(name: targetName)
                            .offset(y: dragOffset.height)
                            // 旋转逻辑：根据拖拽稍微左右摆动，增加真实感
                            .rotationEffect(.degrees(Double(dragOffset.width) * 0.1))
                            .rotation3DEffect(
                                .degrees(Double(dragOffset.height) * 0.05),
                                axis: (x: 1, y: 0, z: 0) // 模拟撕开时的翻起效果
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { val in
                                        handleDrag(val)
                                    }
                                    .onEnded { val in
                                        handleDragEnd(val)
                                    }
                            )
                            .zIndex(10)
                    }
                    
                    // --- 粒子特效层 ---
                    if showParticles {
                        RipParticlesView()
                    }
                }
                
                Spacer()
                
                // 4. 底部按钮
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white.opacity(0.8))
                        .background(Circle().fill(.black.opacity(0.2)))
                }
                .padding(.bottom, 50)
                .opacity(isRipped ? 0 : 1)
            }
        }
        .onAppear {
            impactLight.prepare()
            impactHeavy.prepare()
        }
    }
    
    // MARK: - 逻辑处理
    
    private func handleDrag(_ val: DragGesture.Value) {
        guard !isRipped else { return }
        
        // 限制只能向下和稍微左右
        let yTranslation = max(0, val.translation.height)
        // 增加阻力感：越往下越难拉（对数增长）
        let resistance = 1.2
        let dampedY = yTranslation / resistance
        
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: val.translation.width * 0.5, height: dampedY)
        }
        
        // 模拟魔术贴撕裂的声音/触感：每隔一段距离震动一次
        if Int(yTranslation) % 10 == 0 && yTranslation > 0 {
            impactLight.impactOccurred(intensity: 0.5 + (yTranslation / 200.0))
        }
    }
    
    private func handleDragEnd(_ val: DragGesture.Value) {
        let threshold: CGFloat = 100 // 撕下的阈值
        
        if val.translation.height > threshold {
            // 成功撕下
            performRip()
        } else {
            // 弹回
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                dragOffset = .zero
            }
            // 失败反馈
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    private func performRip() {
        isRipped = true
        impactHeavy.impactOccurred(intensity: 1.0)
        
        // 1. 播放飞出动画
        withAnimation(.easeIn(duration: 0.15)) {
            dragOffset.height = 600
        }
        
        // 2. 显示粒子
        showParticles = true
        
        // 3. 执行回调
        Task {
            // 延迟一点点，让动画飞一会
            try? await Task.sleep(nanoseconds: 200_000_000)
            await onRip()
        }
    }
}

// MARK: - 子组件：名牌卡片
struct NameTagCard: View {
    let name: String
    
    var body: some View {
        ZStack {
            // 纸张纹理感
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
            
            // 边框细节（模拟布料缝线或边缘）
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(white: 0.9), lineWidth: 4)
            
            // 名字
            HStack(spacing: 0) {
                // 左侧加一个小图标或者条纹，增加设计感
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 8)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
                
                Spacer()
                
                Text(name)
                    // 使用更粗旷的字体
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    // 名字太长自动缩放
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                
                Spacer()
            }
            
            // 底部撕扯指引纹理
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<15) { _ in
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

// MARK: - 子组件：粒子特效 (撕裂瞬间)
struct RipParticlesView: View {
    @State private var time = 0.0
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees(360 * now)
                
                // 绘制爆炸线
                for i in 0..<12 {
                    let rotation = Angle.degrees(Double(i) * 30) + angle
                    var contextCopy = context
                    contextCopy.rotate(by: rotation)
                    contextCopy.translateBy(x: 0, y: -80 - (time * 200)) // 扩散
                    
                    let path = Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: 0, y: 20))
                    }
                    contextCopy.stroke(
                        path,
                        with: .color(.white),
                        lineWidth: 3 * (1 - time) // 逐渐变细
                    )
                }
            }
            .opacity(1 - time) // 逐渐消失
        }
        .frame(width: 300, height: 300)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                time = 1.0
            }
        }
    }
}

// MARK: - Preview
#Preview("Optimized Rip UI") {
    ZStack {
        Map().ignoresSafeArea() // 背景模拟
        
        RipNametagView(
            targetName: "RunningMan_007",
            onRip: {
                print("⚡️ RIPPED!")
            },
            onCancel: {
                print("❌ Cancelled")
            }
        )
    }
}
