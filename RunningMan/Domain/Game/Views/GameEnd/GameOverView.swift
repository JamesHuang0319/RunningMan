//
//  GameOverView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI

struct GameOverView: View {
    @Environment(GameStore.self) var game
    
    // ✅ 新增：控制顶部弹出指令的状态
    @State private var transientInstruction: String? = nil

    private var brandGradient: LinearGradient {
        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack(alignment: .top) { // ✅ 顶部对齐，方便弹出提示
            // 1. 亮色背景层
            LinearGradient(colors: [Color(hex: "F2F5F8"), .white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // 2. 核心内容
            VStack(spacing: 0) {
                Spacer()

                // 🎯 结算主卡片
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.orange.gradient)
                    }
                    .padding(.top, 10)

                    VStack(spacing: 8) {
                        Text("任务完成")
                            .font(.system(.title, design: .rounded).bold())
                            .foregroundStyle(.primary)
                        
                        Text("行动代号: \(game.roomId?.uuidString.prefix(8).uppercased() ?? "OFFLINE")")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Divider().background(Color.black.opacity(0.05))

                    VStack(spacing: 12) {
                        statRow(title: "当前角色", value: game.me?.role.rawValue ?? "-", icon: "person.text.rectangle")
                        statRow(title: "游戏区域", value: game.selectedRegion.name, icon: "map")
                    }
                    .padding(.vertical, 10)
                }
                .padding(24)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 10) // 柔和扩散阴影
                .padding(.horizontal, 24)

                Spacer()

                // 3. 🎮 路由操作区
                VStack(spacing: 16) {
                    if game.isHost {
                        // 房主操作
                        Button {
                            Task { await game.hostRematch() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("发起再来一局")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(brandGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)
                        }
                    } else {
                        // 普通玩家：等待状态展示
                        HStack {
                            ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                            Text("等待房主决策...")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // ✅ 修改：统一调用 exitGame()。
                    // 逻辑说明：房主点这个会调用 closeRoom，让所有人的 phase 变成 setup 从而强制退回主页。
                    Button {
                        Task { await game.exitGame() }
                    } label: {
                        Text(game.isHost ? "解散房间并退出" : "离开并返回首页")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 30)
            }
            
            // 4. ✅ 顶部弹出式“战术指令” (不再挤在卡片下方)
            if let message = transientInstruction {
                TacticalAlertView(message: message)
                    .padding(.top, 60) // 避开灵动岛/刘海区域
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .navigationBarBackButtonHidden(true)
        // ✅ 核心触发：监听 phaseInstruction 变化并执行动画
        .onChange(of: game.phaseInstruction) { _, newValue in
            triggerInstruction(newValue)
        }
        .onAppear {
            triggerInstruction(game.phaseInstruction)
        }
    }

    // MARK: - Helper Methods

    private func triggerInstruction(_ message: String) {
        guard !message.isEmpty else { return }
        
        // 弹出动画
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            transientInstruction = message
        }
        
        // 4.5秒后自动收起
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeIn(duration: 0.5)) {
                if transientInstruction == message {
                    transientInstruction = nil
                }
            }
        }
    }

    private func statRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(.primary)
        }
    }
}


