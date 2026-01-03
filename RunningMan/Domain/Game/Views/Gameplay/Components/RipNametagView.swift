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
    
    @State private var dragOffset: CGFloat = 0
    @State private var isRipped = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack {
                Spacer()
                Text("向下滑动撕下名牌！")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 5)
                    .padding(.bottom, 20)
                
                // 名牌区域
                ZStack(alignment: .top) {
                    // 背底
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 200, height: 100)
                    
                    // 可撕的名牌
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .shadow(radius: 5)
                        
                        Text(targetName)
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 200, height: 100)
                    .offset(y: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) * 0.05)) // 稍微旋转增加真实感
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                if val.translation.height > 0 { // 只能向下
                                    dragOffset = val.translation.height
                                }
                            }
                            .onEnded { val in
                                if val.translation.height > 120 {
                                    // 撕下来了！
                                    isRipped = true
                                    withAnimation(.easeIn(duration: 0.2)) {
                                        dragOffset = 600 // 飞出屏幕
                                    }
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    Task { await onRip() }
                                } else {
                                    // 弹回去
                                    withAnimation(.spring()) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
                
                Spacer()
                
                Button("取消") { onCancel() }
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 50)
            }
        }
    }
}


//
//  RipNametagView_Previews.swift
//

#Preview("Rip Nametag") {
    ZStack {
        // 模拟地图背景
        Map()
            .ignoresSafeArea()
            .blur(radius: 2) // 模拟背景虚化
        
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
