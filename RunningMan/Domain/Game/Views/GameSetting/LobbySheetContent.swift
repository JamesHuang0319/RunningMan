//
//  LobbySheetContent.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/26.
//

import SwiftUI

struct LobbySheetContent: View {
    @Environment(GameStore.self) private var game

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {  // 稍微加大一点间距，防止太挤

                    // 1. 区域选择 (Target Zone)
                    NavigationLink {
                        if game.isHost { RegionSelectionView() }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .frame(width: 48, height: 48)
                                .background(
                                    .orange.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("目标战区")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(game.selectedRegion.name)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if game.isHost {
                                HStack(spacing: 4) {
                                    Text("更换")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            } else {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    }
                    .disabled(!game.isHost)

                    // 2. 身份选择 (Select Identity)
                    // ✅ 确保这个 VStack 存在！
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择身份")
                            .font(.headline)
                            .padding(.leading, 4)  // 对齐视觉

                        HStack(spacing: 10) {
                            RoleCard(
                                role: .runner,
                                icon: "figure.run",
                                color: .blue,
                                isSelected: game.meRole == .runner
                            ) {
                                updateRoleWithDebounce(.runner)
                            }
                            RoleCard(
                                role: .hunter,
                                icon: "eye.fill",
                                color: .red,
                                isSelected: game.meRole == .hunter
                            ) {
                                updateRoleWithDebounce(.hunter)
                            }
                            RoleCard(
                                role: .spectator,
                                icon: "camera.fill",
                                color: .gray,
                                isSelected: game.meRole == .spectator
                            ) {
                                updateRoleWithDebounce(.spectator)
                            }
                        }
                    }

                    Divider()

                    // 3. 玩家列表
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("已就位")
                                .font(.headline)
                            Spacer()
                            Text("\(game.lobbyPlayers.count) 人")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(game.lobbyPlayers) { player in
                            LobbyPlayerRow(player: player)
                        }

                        if game.lobbyPlayers.isEmpty {
                            ContentUnavailableView(
                                "暂无玩家",
                                systemImage: "person.slash"
                            )
                        }
                    }

                    // 底部垫片：保证内容能滚上来
                    Color.clear.frame(height: 100)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)

            // 4. 底部按钮栏
            // ✅ 修复：使用 .ultraThinMaterial 匹配 Sheet 的质感
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    // 加一条极淡的分割线，增加精致感
                    Divider()
                        .overlay(Color.primary.opacity(0.05))

                    Group {
                        if game.isHost {
                            Button {
                                Task { await game.startRoomGame() }
                            } label: {
                                HStack {
                                    Image(systemName: "flag.fill")
                                    Text("开始游戏")
                                }
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                // 绿色按钮本身保持不透明
                                .background(
                                    game.canStartGame
                                        ? Color.green : Color.gray.opacity(0.3)
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(
                                    color: .green.opacity(0.3),
                                    radius: 8,
                                    y: 4
                                )  // 加点投影更有质感
                            }
                            .disabled(!game.canStartGame)
                        } else {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("等待房主下达指令...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                // ✅ 关键修改：使用 .ultraThinMaterial 而不是 .bar
                // 这样它就会和 Sheet 的背景融为一体，实现你要的“透明感”
                .background(.ultraThinMaterial)
            }
        }
    }

    private func updateRoleWithDebounce(_ role: GameRole) {
        game.updateRole(to: role)
    }
}

// MARK: - Subviews (功能组件)

// 1. 区域选择页面 (从 Sheet 里 Push 进去)
struct RegionSelectionView: View {
    @Environment(GameStore.self) private var game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(GameRegion.allCSURegions) { region in
            Button {
                Task {
                    // 1. 本地选中
                    game.selectedRegion = region
                    // 2. 如果是房主，同步到服务器 (Lock Region)
                    Task {
                        await game.lockSelectedRegion()
                    }

                    // 3. 选完自动返回上一页
                    //dismiss()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(region.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("半径: \(Int(region.initialRadius))米")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // 选中状态打勾
                    if game.selectedRegion.id == region.id {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("更换战区")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 2. 角色选择卡片 (RoleCard)
struct RoleCard: View {
    let role: GameRole
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(role.rawValue.capitalized)
                    .font(.caption2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            // 选中时高亮背景，未选中时浅灰色
            .background(
                isSelected ? color.opacity(0.15) : Color.primary.opacity(0.03)
            )
            .foregroundStyle(isSelected ? color : .secondary)
            // 选中时加描边
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)  // 关键：防止在 ScrollView/List 中点击范围异常
    }
}

// 3. 玩家列表行 (LobbyPlayerRow)
struct LobbyPlayerRow: View {
    let player: LobbyPlayerDisplay

    var body: some View {
        HStack(spacing: 12) {
            // 头像/角色图标
            ZStack {
                Circle()
                    .fill(roleColor(player.role).opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: roleIcon(player.role))
                    .font(.system(size: 20))
                    .foregroundStyle(roleColor(player.role))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(player.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    if player.isMe {
                        Text("我")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.gradient, in: Capsule())
                    }
                }

                Text(player.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            
            
            switch player.badge {
            case .connecting:
                Label("连接中", systemImage: "wifi")
                    .foregroundStyle(.secondary)
            case .offline:
                Label("离线", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            case .online:
                if player.isStale {
                    Label("信号弱", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Label("在线", systemImage: "circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                }
            }


        }
        .padding(12)
        .background(Color.primary.opacity(0.03))  // 每一行有个浅色底
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // 辅助函数：根据角色返回颜色
    func roleColor(_ role: GameRole) -> Color {
        switch role {
        case .runner: return .blue
        case .hunter: return .red
        case .spectator: return .gray
        }
    }

    // 辅助函数：根据角色返回图标
    func roleIcon(_ role: GameRole) -> String {
        switch role {
        case .runner: return "figure.run"
        case .hunter: return "eye.fill"
        case .spectator: return "camera.fill"
        }
    }

}

// MARK: - Previews
//
//#Preview("Lobby Sheet (Host)") {
//    // 使用闭包构建 Mock 数据，避免 ViewBuilder 语法报错
//    let mockHostGame: GameStore = {
//        let store = GameStore()
//        let myId = UUID()
//        let roomId = UUID()
//
//        // 1. 基础信息
//        store.meId = myId
//        store.roomId = roomId
//        store.selectedRegion = GameRegion.allCSURegions.first!
//
//        // 2. 房间信息 (我是房主)
//        store.room = Room(
//            id: roomId,
//            status: "waiting",
//            rule: [:],
//            regionId: store.selectedRegion.id,
//            createdBy: myId,  // ✅ 关键：这里填自己，就是房主
//            createdAt: Date(),
//        )
//
//        // 3. 模拟玩家 (包含自己、其他玩家、离线玩家)
//        store.statesByUserId = [
//            // 自己 (Runner)
//            myId: RoomPlayerState(
//                roomId: roomId,
//                userId: myId,
//                role: .runner,
//                status: .active,
//                lat: 0,
//                lng: 0,
//                updatedAt: Date()
//            ),
//
//            // 别人 (Hunter)
//            UUID(): RoomPlayerState(
//                roomId: roomId,
//                userId: UUID(),
//                role: .hunter,
//                status: .active,
//                lat: 0,
//                lng: 0,
//                updatedAt: Date()
//            ),
//
//            // 别人 (Spectator - 模拟离线，时间设为很久前)
//            UUID(): RoomPlayerState(
//                roomId: roomId,
//                userId: UUID(),
//                role: .spectator,
//                status: .active,
//                lat: 0,
//                lng: 0,
//                updatedAt: Date().addingTimeInterval(-100)
//            ),
//        ]
//
//        return store
//    }()
//
//    // Sheet 只有半屏，用 Color.gray 模拟背景以便观察
//    ZStack {
//        Color.gray.ignoresSafeArea()
//
//        // 模拟 Sheet 的展示环境
//        VStack {
//            Spacer()
//            LobbySheetContent()
//                .environment(mockHostGame)
//                .background(.regularMaterial)  // 模拟 Sheet 背景
//                .clipShape(RoundedRectangle(cornerRadius: 24))
//        }
//    }
//}
