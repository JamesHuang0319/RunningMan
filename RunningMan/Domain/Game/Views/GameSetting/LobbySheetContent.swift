//
//  LobbySheetContent.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/26.
//

import SwiftUI

struct LobbySheetContent: View {
    @Environment(GameStore.self) private var game

    // ✅ 从外部 Sheet 传进来
    @Binding var selectedDetent: PresentationDetent

    // ✅ 用状态驱动导航
    @State private var goRegion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {  // 稍微加大一点间距，防止太挤
                    
                    // 1. 区域选择
                    targetZoneSection
                    
                    // 2. 身份选择
                    identitySelectionSection

                    Divider()

                    // 3. 玩家列表
                    playerListSection

                    // 底部垫片：保证内容能滚上来
                    Color.clear.frame(height: 100)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $goRegion) {
                RegionSelectionView()
            }
            // 4. 底部按钮栏
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .tint(.primary)
        .background(Color.clear)
    }

    private func updateRoleWithDebounce(_ role: GameRole) {
        game.updateRole(to: role)
    }
    
    // MARK: - Lobby 内容拆分 (解决编译器超时)

    private var targetZoneSection: some View {
        Button {
            guard game.isHost else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedDetent = .medium
            }
            DispatchQueue.main.async {
                goRegion = true
            }
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!game.isHost)
    }

    private var identitySelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择身份")
                .font(.headline)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                RoleCard(role: .runner, icon: "figure.run", color: .blue, isSelected: game.meRole == .runner) {
                    updateRoleWithDebounce(.runner)
                }
                RoleCard(role: .hunter, icon: "eye.fill", color: .red, isSelected: game.meRole == .hunter) {
                    updateRoleWithDebounce(.hunter)
                }
                RoleCard(role: .spectator, icon: "camera.fill", color: .gray, isSelected: game.meRole == .spectator) {
                    updateRoleWithDebounce(.spectator)
                }
            }
        }
    }

    private var playerListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已就位").font(.headline)
                Spacer()
                Text("\(game.lobbyPlayers.count) 人").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(game.lobbyPlayers) { player in
                LobbyPlayerRow(player: player)
            }

            if game.lobbyPlayers.isEmpty {
                ContentUnavailableView("暂无玩家", systemImage: "person.slash")
            }
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.primary.opacity(0.05))
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
                        .background(game.canStartGame ? Color.green : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(!game.canStartGame)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("等待房主下达指令...").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Subviews

// 1. 区域选择页面
struct RegionSelectionView: View {
    @Environment(GameStore.self) private var game
    @Environment(\.dismiss) private var dismiss
    
    @State private var isProcessing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(GameRegion.allCSURegions) { region in
                    regionRow(region)
                }
            }
            .padding(20)
            Color.clear.frame(height: 100)
        }
        .background(Color.clear)
        .scrollContentBackground(.hidden) // 加上这一行，强制隐藏所有系统底色
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            topTitleBar
        }
    }

    @ViewBuilder
    private func regionRow(_ region: GameRegion) -> some View {
        let isSelected = game.selectedRegion.id == region.id
        Button {
            if !isProcessing && !isSelected {
                selectRegion(region)
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(region.name)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.7))

                    Text("半径: \(Int(region.initialRadius))米")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // 勾选框：也改得更高级一点
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.2))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            // 🔥 关键：不要用白色！
            .background {
                if isSelected {
                    // 选中时：用极淡的黑色产生“凹陷感”
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                } else {
                    // 未选中时：完全透明，只靠边框
                    Color.clear
                }
            }
            // 🔥 用一层极其细微的白边/黑边产生“玻璃切割”感
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(isSelected ? 0.15 : 0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var topTitleBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                Text("更换战区").font(.system(.title3, design: .rounded).bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            Divider().opacity(0.1)
        }
        .background(.ultraThinMaterial)
    }

    private func selectRegion(_ region: GameRegion) {
        isProcessing = true
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.2)) {
            game.selectedRegion = region
        }
        Task {
            await game.lockSelectedRegion()
            isProcessing = false
        }
    }
}

// 2. 角色选择卡片
struct RoleCard: View {
    let role: GameRole
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(role.rawValue.capitalized).font(.caption2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.15) : Color.primary.opacity(0.03))
            .foregroundStyle(isSelected ? color : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// 3. 玩家列表行
struct LobbyPlayerRow: View {
    let player: LobbyPlayerDisplay

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(roleColor(player.role).opacity(0.1)).frame(width: 44, height: 44)
                Image(systemName: roleIcon(player.role)).font(.system(size: 20)).foregroundStyle(roleColor(player.role))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(player.displayName).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if player.isMe {
                        Text("我").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.gradient, in: Capsule())
                    }
                }
                Text(player.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            badgeView
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var badgeView: some View {
        switch player.badge {
        case .connecting: Label("连接中", systemImage: "wifi").foregroundStyle(.secondary)
        case .offline: Label("离线", systemImage: "wifi.slash").foregroundStyle(.secondary)
        case .online:
            if player.isStale {
                Label("信号弱", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            } else {
                Label("在线", systemImage: "circle.fill").labelStyle(.iconOnly).foregroundStyle(.green)
            }
        }
    }

    func roleColor(_ role: GameRole) -> Color {
        switch role { case .runner: return .blue; case .hunter: return .red; case .spectator: return .gray }
    }
    func roleIcon(_ role: GameRole) -> String {
        switch role { case .runner: return "figure.run"; case .hunter: return "eye.fill"; case .spectator: return "camera.fill" }
    }
}

// 辅助组件
private struct CompactSectionSpacingIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) { content.listSectionSpacing(.compact) } else { content }
    }
}
