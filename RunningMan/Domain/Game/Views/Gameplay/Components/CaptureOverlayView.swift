//
//  CaptureOverlayView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/31.
//

import SwiftUI

struct CaptureOverlayView: View {
    let type: ResultType
    let message: String
    var onDismiss: () -> Void

    enum ResultType {
        case success // 抓到了
        case busted  // 被抓了
        case escaped // 逃脱了
    }

    @State private var scale: CGFloat = 2.0
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = -20

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 16) {
                // 核心印章
                ZStack {
                    Circle()
                        .stroke(color, lineWidth: 8)
                        .frame(width: 220, height: 220)
                    
                    Text(title)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(-15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(color, lineWidth: 5)
                                .frame(width: 240, height: 90)
                                .rotationEffect(.degrees(-15))
                        )
                }
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                .opacity(opacity)
                
                Text(message)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                    .opacity(opacity)
            }
        }
        .onAppear {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.0
                opacity = 1.0
                rotation = 0
            }
            
            // 3秒后自动消失
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                onDismiss()
            }
        }
    }
    
    var color: Color {
        switch type {
        case .success: return .yellow
        case .busted: return .red
        case .escaped: return .green
        }
    }
    
    var title: String {
        switch type {
        case .success: return "CAUGHT!"
        case .busted: return "BUSTED"
        case .escaped: return "ESCAPED"
        }
    }
}
