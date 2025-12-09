//
//  SetupView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI
import MapKit

struct SetupView: View {
    @Environment(GameManager.self) var game
    @State private var camera: MapCameraPosition = .automatic
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Map(position: $camera) {
                MapCircle(center: game.selectedRegion.center,
                          radius: game.selectedRegion.initialRadius)
                    .foregroundStyle(.blue.opacity(0.10))
                    .stroke(.blue.opacity(0.9), lineWidth: 2)
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            // ✅ 顶部：自定义“玻璃标题条”，比 navigation large title 干净太多
            VStack(spacing: 0) {
                topHeader
                Spacer()
            }
            .safeAreaPadding(.top, 10)

            // ✅ 底部：sheet（你现在已经有了）
            VStack {
                Spacer()
                setupSheet
            }
            .padding(.bottom, 10)
        }
        .onAppear { flyToSelected() }
        .onChange(of: game.selectedRegion) { _, _ in flyToSelected() }
    }

    private var topHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Running Man")
                    .font(.title2.bold())
                Text("选择区域与角色，准备开局。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard(cornerRadius: 18)
        .padding(.horizontal, 12)
    }

    private var setupSheet: some View {
        // 这里复用你现有的 setupSheet（折叠/展开 + 区域/角色 + 开始按钮）
        // 你可以直接把我上次给你的 setupSheet 粘进来
        SetupSheet(isExpanded: $isExpanded)
            .environment(game)
            .padding(.horizontal, 12)
    }

    private func flyToSelected() {
        withAnimation(.easeInOut(duration: 0.9)) {
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

#Preview("SetupView - Sheet") {
    let mock = GameManager()
    mock.phase = .setup
    return SetupView()
        .environment(mock)
}
