//
//  LobbyView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/26.
//

import MapKit
import SwiftUI

struct LobbyView: View {
    @Environment(GameStore.self) private var game
    @Environment(\.dismiss) private var dismiss

    // 📷 地图视角
    @State private var camera: MapCameraPosition = .automatic

    // ⚠️ 修复 Detent 警告：定义一个常量，确保初始值和列表值完全相等
    private static let initialDetent: PresentationDetent = .fraction(0.26)
    @State private var selectedDetent: PresentationDetent = initialDetent

    // 📋 复制反馈状态
    @State private var isCopied: Bool = false

    var body: some View {
        ZStack(alignment: .top) {

            // 1. 底层全屏地图
            Map(position: $camera) {
                MapCircle(
                    center: game.selectedRegion.center,
                    radius: game.selectedRegion.initialRadius
                )
                .foregroundStyle(.orange.opacity(0.15))
                .stroke(.orange.opacity(0.8), lineWidth: 2)
            }
            .mapStyle(
                .standard(
                    elevation: .realistic,
                    pointsOfInterest: .excludingAll
                )
            )
            .ignoresSafeArea()

            // 2. 顶部悬浮按钮组
            HStack(alignment: .top) {
                // 离开按钮
                Button {
                    Task { await game.leaveRoom() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))  // 稍微加粗更精致
                        .foregroundStyle(.black.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())  // ✅ 改为亮色玻璃材质，增加通透感
                        .shadow(
                            color: .black.opacity(0.1),
                            radius: 8,
                            x: 0,
                            y: 4
                        )  // ✅ 增加软阴影，营造层次感
                }

                Spacer()

                // 复制 ID 按钮
                if let roomId = game.roomId {
                    Button {
                        UIPasteboard.general.string = roomId.uuidString
                        withAnimation { isCopied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { isCopied = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName: isCopied
                                    ? "checkmark" : "doc.on.doc"
                            )
                            .contentTransition(.symbolEffect(.replace))
                            Text(isCopied ? "已复制" : "复制房号")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(isCopied ? .green : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        // 使用 AnyShapeStyle 确保类型对齐
                        .background(
                            isCopied
                                ? AnyShapeStyle(.white)
                                : AnyShapeStyle(Color.blue)
                        )
                        .clipShape(Capsule())
                        // ✅ 使用彩色发光阴影，增加视觉参差感
                        .shadow(
                            color: (isCopied ? Color.green : Color.blue)
                                .opacity(0.3),
                            radius: 12,
                            x: 0,
                            y: 6
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            // ✅ 调整高度的地方：
            // 因为加了下面的 ignoresSafeArea，这里的数字是从屏幕物理顶端起算的
            // 建议：54-60 左右可以避开刘海屏/灵动岛并处于舒适位置；如果你想更高，就调小这个值。
            .padding(.top, 80)
            .ignoresSafeArea(edges: .top)  // ✅ 关键：忽略顶部安全区域，解决位置“调不上去”的问题
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { flyToSelected() }
        .onChange(of: game.selectedRegion) { _, _ in flyToSelected() }

        // ✅ Sheet 配置
        .sheet(isPresented: .constant(true)) {
            LobbySheetContent()
                .environment(game)
                // 使用静态常量，解决 "Cannot set selected sheet detent" 警告
                .presentationDetents(
                    [Self.initialDetent, .medium, .large],
                    selection: $selectedDetent
                )
                .presentationBackgroundInteraction(.enabled)
                .presentationCornerRadius(24)
                .presentationBackground(.ultraThinMaterial)  // 统一使用极薄材质
                .interactiveDismissDisabled()
        }
        #if DEBUG
            .overlay(alignment: .topTrailing) {
                DebugOverlay()
                .environment(game)
                .padding(.trailing, 14)
                .padding(.top, 90)  // 你要避开顶部 HUD 就调这里
                .zIndex(1_000_000)
            }
        #endif

    }

    private func flyToSelected() {
        withAnimation(.easeInOut(duration: 1.0)) {
            camera = .region(
                MKCoordinateRegion(
                    center: game.selectedRegion.center,
                    latitudinalMeters: game.selectedRegion.initialRadius * 2.8,
                    longitudinalMeters: game.selectedRegion.initialRadius * 2.8
                )
            )
        }
    }
}
