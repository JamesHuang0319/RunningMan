//
//  MainMapView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.

import MapKit
import SwiftUI

struct MainMapView: View {
    @Environment(GameStore.self) private var game
    @State private var position: MapCameraPosition = .userLocation(
        fallback: .automatic
    )
    @Namespace private var mapScope

    // UI 状态
    @State private var isBackpackExpanded = false
    @State private var showHandbook = false
    @State private var activeNotification: FruitSkill? = nil

    // ✅ 用于控制顶部弹出战术提醒的局部状态
    @State private var transientInstruction: String? = nil

    // 新增：撕名牌相关状态
    @State private var showRipUI = false
    @State private var targetToRip: PlayerDisplay? = nil
    @State private var showCaptureOverlay = false
    @State private var captureResult: (Bool, String) = (true, "")  // (isSuccess, message)

    @State private var mySkills: [FruitSkill] = [
        FruitSkill.allSkills[0], FruitSkill.allSkills[1],
    ]

    // 品牌渐变色
    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // --- 抓捕结果盖章动画（最上层）---
            if showCaptureOverlay {
                CaptureOverlayView(
                    type: captureResult.0 ? .success : .busted,  // ← 改用 type 参数
                    message: captureResult.1
                ) {
                    withAnimation {
                        showCaptureOverlay = false
                    }
                    // 可选：如果你以后需要检查游戏结束，可以在这里加逻辑
                    // game.checkGameEnd()  // ← 删除这行，因为 GameStore 没有这个方法
                }
                .zIndex(999)
                .transition(.opacity)  // 可加个淡出动画更丝滑
            }
            // --- 1. 地图背景层 ---
            Map(position: $position, scope: mapScope) {
                UserAnnotation()

                ForEach(game.players) { p in
                    if !p.isMe && !p.isOffline {
                        // 实时计算距离（单位：米）
                        let distance = game.distanceTo(p.coordinate)

                        Annotation(p.displayName, coordinate: p.coordinate) {

                            Button {
                                DLog.info("👇 [UI] Clicked player: \(p.displayName), dist: \(Int(distance))m") // ✅ 补上日志
                                // --- 点击逻辑 ---
                                // 猎人且距离 < 10m -> 触发撕名牌 UI
                                if distance < 10 && game.meRole == .hunter
                                    && p.role == .runner
                                {

                                    UIImpactFeedbackGenerator(style: .heavy)
                                        .impactOccurred()
                                    targetToRip = p
                                    withAnimation { showRipUI = true }

                                } else {
                                    // 否则正常导航
                                    Task { await game.navigate(to: p.id) }
                                }
                            } label: {
                                // --- 图标 UI ---
                                PlayerAnnotationView(
                                    player: p,
                                    distance: distance
                                )
                                .frame(width: 50, height: 50)
                                .contentShape(Rectangle())  // 扩大点击区域
                            }
                            .buttonStyle(.plain)  // 去掉按钮默认样式

                        }
                        // ✅ 关键：隐藏系统自带的文本标题，只显示我们的 View
                        .annotationTitles(.hidden)
                    }
                }

                if let zone = game.safeZone {
                    MapCircle(center: zone.center, radius: zone.radius)
                        .foregroundStyle(.cyan.opacity(0.12))
                        .stroke(.cyan.gradient, lineWidth: 2)
                }
                if let route = game.currentRoute {
                    MapPolyline(route).stroke(.blue.gradient, lineWidth: 6)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()

            // --- 2. 静态 UI 层 (HUD + 四角工具栏) ---
            VStack(spacing: 0) {
                Spacer().frame(height: 64)
                GameHUDView()
                HStack(alignment: .top) {
                    // 【左上角】：工具塔
                    VStack(spacing: 12) {
                        MapUserLocationButton(scope: mapScope).buttonStyle(
                            .plain
                        )
                        Button {
                            if let center = game.safeZone?.center {
                                withAnimation(.spring()) {
                                    position = .region(
                                        MKCoordinateRegion(
                                            center: center,
                                            latitudinalMeters: 800,
                                            longitudinalMeters: 800
                                        )
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "map.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.blue)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 4)
                        }
                        MapPitchToggle(scope: mapScope)
                        MapCompass(scope: mapScope)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 20)

                    Spacer()

                    // 【右上角】：说明书
                    VStack(alignment: .trailing, spacing: 12) {
                        Button {
                            withAnimation(.spring()) {
                                showHandbook.toggle()
                                if showHandbook { isBackpackExpanded = false }
                            }
                        } label: {
                            Image(
                                systemName: showHandbook
                                    ? "xmark" : "book.pages.fill"
                            )
                            .font(.system(size: 20, weight: .bold))
                            .modifier(GlassButtonStyle(isActive: showHandbook))
                        }

                        if showHandbook {
                            SkillHandbookView()
                                .transition(
                                    .move(edge: .trailing).combined(
                                        with: .opacity
                                    )
                                )
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 20)
                }
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

            // --- 3. 动态通知层 ---
            VStack(spacing: 10) {
                if let message = transientInstruction {
                    TacticalAlertView(message: message)
                }
                if let skill = activeNotification {
                    SkillFeedbackOverlay(skill: skill)
                }
            }
            .padding(.top, 145)
            .allowsHitTesting(false)

            // --- 4. 撕名牌确认 UI（模态层）---
            if showRipUI, let target = targetToRip {
                RipNametagView(
                    targetName: target.displayName,
                    onRip: {
                        Task {
                            await attemptTag(targetId: target.id)
                        }
                    },
                    onCancel: {
                        withAnimation { showRipUI = false }
                    }
                )
                .zIndex(100)
                .transition(.scale.combined(with: .opacity))
            }

            // --- 5. 底部 UI ---
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    HoldToEndButton(holdDuration: 1.5) {
                        if game.isHost {
                            await game.hostEndGame()
                        } else {
                            game.playerSurrender()
                        }
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(spacing: 14) {
                        if isBackpackExpanded {
                            ForEach(mySkills) { skill in
                                Button {
                                    useSkill(skill)
                                } label: {
                                    Text(skill.icon).font(.system(size: 26))
                                        .modifier(
                                            GlassButtonStyle(
                                                size: 54,
                                                color: skill.color
                                            )
                                        )
                                }
                                .transition(
                                    .move(edge: .bottom).combined(with: .scale)
                                        .combined(with: .opacity)
                                )
                            }
                        }

                        Button {
                            withAnimation(
                                .spring(response: 0.4, dampingFraction: 0.7)
                            ) {
                                isBackpackExpanded.toggle()
                                if isBackpackExpanded { showHandbook = false }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(brandGradient)
                                    .frame(width: 64, height: 64)
                                    .shadow(
                                        color: .blue.opacity(0.4),
                                        radius: 10,
                                        y: 5
                                    )
                                Image(systemName: "backpack.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                                    .rotationEffect(
                                        .degrees(isBackpackExpanded ? -10 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .mapScope(mapScope)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: game.phaseInstruction) { _, newValue in
            triggerInstruction(newValue)
        }
        .onAppear {
            triggerInstruction(game.phaseInstruction)
        }
    }

    // MARK: - Helper Methods

    private func useSkill(_ skill: FruitSkill) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            activeNotification = skill
        }
        withAnimation(.spring()) {
            mySkills.removeAll(where: { $0.id == skill.id })
            if mySkills.isEmpty { isBackpackExpanded = false }
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeOut(duration: 0.5)) { activeNotification = nil }
        }
    }

    private func triggerInstruction(_ message: String) {
        guard !message.isEmpty else { return }
        withAnimation(.easeIn(duration: 0.2)) {
            transientInstruction = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                transientInstruction = message
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeIn(duration: 0.5)) {
                    if transientInstruction == message {
                        transientInstruction = nil
                    }
                }
            }
        }
    }

    // 统一的抓捕逻辑（原 tryAttemptTag 内容，稍作精简）
    @MainActor
    private func attemptTag(targetId: UUID) async {
        DLog.info("🚀 [Logic] attemptTag START target=\(targetId)") // ✅ 补上日志
        
        withAnimation { showRipUI = false }

        // 基本前置检查
        guard game.phase == .playing else {
            DLog.warn("🛑 [Logic] blocked: phase is \(game.phase)") // ✅ 补上日志
            triggerInstruction("❌ 只能在行动阶段抓捕")
            return
        }
        guard game.meRole == .hunter else {
            triggerInstruction("❌ 只有猎人可以抓捕")
            return
        }

        do {
            DLog.info("📡 [Logic] Calling RPC...") // ✅ 补上日志
            let result = try await game.attemptTag(targetUserId: targetId)
            DLog.info("✅ [Logic] RPC Result: ok=\(result.ok)") // ✅ 补上日志
           

            if result.ok {
                // 距离文字
                let distText =
                    result.dist_m.map { String(format: "%.1f", $0) } ?? "-"

                // 判断是否是最终胜利
                let isVictory =
                    (result.remaining_runners ?? 1) <= 0
                    || result.game_ended == true

                let message: String
                if isVictory {
                    message = "最终抓捕成功！\n猎人团队获得胜利！🎉\n距离 \(distText) 米"
                    // 可选：更强的震动反馈
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred(
                        intensity: 1.0
                    )
                } else {
                    let remaining = result.remaining_runners ?? 0
                    message = "抓捕成功！\n距离 \(distText) 米｜剩余逃跑者 \(remaining)"
                }

                captureResult = (true, message)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showCaptureOverlay = true
                }
            } else {
                // 失败统一走战术提醒
                // （将来如果有特殊失败原因，比如被技能反制，可以改成显示 busted 动画）
                triggerInstruction(humanizeAttemptTagReason(result))
            }
        } catch {
            DLog.err("🔥 [Logic] RPC Error: \(error)") // ✅ 补上日志
            triggerInstruction("❌ 抓捕请求失败：\(error.localizedDescription)")
        }
    }

    private func humanizeAttemptTagReason(_ r: AttemptTagResult) -> String {
        switch r.reason {
        case "not_authenticated": return "❌ 未登录"
        case "room_not_playing": return "❌ 房间未在进行中：\(r.room_status ?? "-")"
        case "not_hunter": return "❌ 你不是猎人"
        case "target_not_runner": return "❌ 对方不是逃跑者"
        case "target_not_active": return "❌ 对方已失效：\(r.target_status ?? "-")"
        case "missing_location": return "❌ 缺少定位（你或对方）"
        case "too_far":
            let distText = r.dist_m.map { String(format: "%.1f", $0) } ?? "-"
            return "❌ 距离太远：\(distText)m"
        case "already_caught_or_missing": return "❌ 对方已被抓或不存在"
        default:
            return "❌ 抓捕失败：\(r.reason ?? "unknown")"
        }
    }
}

// 下面的组件保持不变（TacticalAlertView、SkillFeedbackOverlay、GlassButtonStyle 等）

// MARK: - 战术弹出提醒组件 (Tactical Alert)

struct TacticalAlertView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.blue)

            Text(message)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.4), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        // ✅ 优雅的非对称转场
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity).combined(
                    with: .scale(scale: 0.8)
                ),
                removal: .opacity.combined(with: .scale(scale: 1.1))
            )
        )
    }
}

// MARK: - 技能反馈组件 (Skill Feedback)

struct SkillFeedbackOverlay: View {
    let skill: FruitSkill
    var body: some View {
        HStack(spacing: 10) {
            Text(skill.icon)
            Text(skill.usageMessage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(skill.color.gradient)
        .clipShape(Capsule())
        .shadow(color: skill.color.opacity(0.4), radius: 8, y: 4)
        // ✅ 优雅的通知转场
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity).combined(
                    with: .scale(scale: 0.8)
                ),
                removal: .opacity.combined(with: .scale(scale: 1.1))
            )
        )
    }
}

// MARK: - 辅助修饰符

struct GlassButtonStyle: ViewModifier {
    var size: CGFloat = 48
    var isActive: Bool = false
    var color: Color = .blue
    func body(content: Content) -> some View {
        content
            .foregroundStyle(isActive ? .white : .primary)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial)
            .background(isActive ? color.opacity(0.6) : Color.clear)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }
}
