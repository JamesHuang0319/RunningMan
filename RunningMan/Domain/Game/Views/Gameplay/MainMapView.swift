//
//  MainMapView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

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
    @State private var activeNotification: ItemDef? = nil

    // 顶部战术提醒
    @State private var transientInstruction: String? = nil

    // 撕名牌 UI（确认仪式）
    @State private var showRipUI = false
    @State private var targetToRip: PlayerDisplay? = nil

    // 抓捕结果盖章 Overlay
    @State private var showCaptureOverlay = false
    @State private var captureResult:
        (CaptureOverlayView.AnimationType, String) = (.hunterCaughtOne, "")
    @State private var overlayID = UUID()
    @State private var currentOverlayPriority: Int = -1
    @State private var overlayDismissTask: Task<Void, Never>? = nil

    private var roleItems: [ItemDef] {
        switch game.meRole {
        case .hunter: return ItemDef.all.filter { $0.type.roleScope == .hunter }
        case .runner: return ItemDef.all.filter { $0.type.roleScope == .runner }
        case .spectator: return []
        }
    }
    @State private var myItems: [ItemDef] = []

    // MARK: - Capture Lock (10m 才能撕；15m 出现抓捕条；锁定滞回保持)
    @State private var lockedTargetId: UUID? = nil
    @State private var lockUntil: Date? = nil

    @State private var captureCandidate: PlayerDisplay? = nil
    @State private var captureDistance: Double? = nil
    @State private var captureState: CaptureState = .idle

    // 用一个轻量 tick 让“锁定过期/距离变化”即便 mapPlayers 没刷新也能更新 UI
    @State private var captureTicker: Int = 0

    enum CaptureState { case idle, inRange, locked }  // locked = 强锁定（点过目标或点过抓捕条）

    // 品牌渐变
    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // ✅ 统一的“背景压暗强度”
    private var ripDimOpacity: Double { 0.55 }  // 你想更黑就 0.55

    var body: some View {
        ZStack(alignment: .top) {

            // 0) ✅ 底层：所有正常游戏界面（Map + HUD + 通知 + 底部UI）
            baseContent
                // ✅ 关键：模糊/压暗作用于“整个世界”，不是只作用地图
                .blur(radius: showRipUI ? 10 : 0)
                .scaleEffect(showRipUI ? 1.02 : 1.0)
                .overlay {
                    if showRipUI {
                        Color.black.opacity(ripDimOpacity)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: showRipUI)
                // ✅ Rip UI 出现时，整个底层不允许交互（避免 HUD/地图穿透）
                .allowsHitTesting(!showRipUI)

            // 1) ✅ Rip 弹层（轻量，不再自己做重背景）
            if showRipUI, let target = targetToRip {
                RipNametagView(
                    targetName: target.displayName,
                    onRip: {
                        guard guardCanAct("👀 你已无法抓捕，正在观战") else { return }
                        Task { await attemptTag(targetId: target.id) }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showRipUI = false
                        }
                    }
                )
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // 2) ✅ 抓捕结果盖章动画（永远最顶层）
            if showCaptureOverlay {
                CaptureOverlayView(
                    type: captureResult.0,
                    message: captureResult.1
                ) {
                    // ✅ 方案 A：关闭由 presentOverlay(req) 的 ttl 负责，这里不要再关
                    // 这里仅保留“胜负后的逻辑”
                    if captureResult.0 == .gameVictory
                        || captureResult.0 == .gameDefeat
                    {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if game.isHost {
                                Task { await game.hostEndGame() }
                            } else {
                                // 等待 Realtime rooms.status=ended
                            }
                        }
                    }
                }
                .id(overlayID)
                .zIndex(2000)
                .transition(.opacity)
            }
        }
        .mapScope(mapScope)
        .toolbar(.hidden, for: .tabBar)

        // --- 生命周期 / 状态监听 ---
        .onAppear {
            myItems = roleItems
            triggerInstruction(game.phaseInstruction)
            refreshCaptureCandidate()
        }

        .onChange(of: game.phaseInstruction) { _, newValue in
            triggerInstruction(newValue)
        }

        // mapPlayers 更新时刷新候选
        .onChange(of: game.mapPlayers) { _, _ in
            guard !showRipUI && !showCaptureOverlay else { return }
            refreshCaptureCandidate()
        }

        // 角色变化时刷新背包道具
        .onChange(of: game.meRole) { _, _ in
            myItems = roleItems
            if isBackpackExpanded {
                withAnimation { isBackpackExpanded = false }
            }
        }

        // ✅ 轻量 ticker：让“锁定过期/距离变化”即便 mapPlayers 没刷新也能更新 UI
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
                guard !showRipUI && !showCaptureOverlay else { continue }
                captureTicker &+= 1
                refreshCaptureCandidate()
            }
        }

        // 圈外暴露提示
        .onChange(of: game.me?.isExposed) { _, newValue in
            guard let exposed = newValue else { return }
            if exposed {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                triggerInstruction("⚠️ 你在圈外，位置已暴露")
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                triggerInstruction("✅ 已回到安全区")
            }
        }
        .onChange(of: game.overlayRequest) { _, req in
            guard let req else { return }

            DLog.info(
                "🟣 MainMapView got overlayRequest type=\(req.type) priority=\(req.priority) ttl=\(req.ttl)"
            )

            // ✅ 唯一入口：统一 presentOverlay
            presentOverlay(req)

            // ✅ 消费掉（one-shot）
            DispatchQueue.main.async {
                game.overlayRequest = nil
            }
        }

    }

    // MARK: - 底层世界（Map + HUD + 通知 + 底部UI）
    private var baseContent: some View {
        ZStack(alignment: .top) {

            // --- 1) 地图背景层 ---
            Map(position: $position, scope: mapScope) {
                UserAnnotation()

                ForEach(game.mapPlayers) { p in
                    let now = Date()
                    let sv = p.stateView

                    let hideForHunter =
                        (game.meRole == .hunter) &&
                        (p.role == .runner) &&
                        sv.isCloaked(now: now) &&
                        !sv.isRevealed(now: now)

                    if !p.isMe,
                       p.status == .active,               // 地图只显示 active（要加 ready 就改成: (p.status == .active || p.status == .ready)
                       !hideForHunter
                    {
                        let distance = game.distanceTo(p.coordinate)

                        Annotation(p.displayName, coordinate: p.coordinate) {
                            Button {
                                DLog.info("👇 [UI] Clicked player: \(p.displayName), dist: \(Int(distance))m")

                                // ✅ 观战者不允许锁定/导航
                                guard guardCanAct() else { return }

                                // ✅ 猎人点 runner：只做锁定
                                if game.meRole == .hunter && p.role == .runner {
                                    lockedTargetId = p.id
                                    lockUntil = Date().addingTimeInterval(2.5)
                                    refreshCaptureCandidate()

                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    triggerInstruction("🎯 已锁定：\(p.displayName)")
                                    return
                                }

                                // ✅ runner / 其他：导航
                                Task { await game.navigate(to: p.id) }
                            } label: {
                                PlayerAnnotationView(player: p, distance: distance)
                                    .opacity(p.isOffline ? 0.35 : 1.0)
                                    .frame(width: 50, height: 50)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
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

            // --- 2) 静态 UI 层 (HUD + 四角工具栏) ---
            VStack(spacing: 0) {
                Spacer().frame(height: 64)
                GameHUDView()

                HStack(alignment: .top) {
                    // 左上：工具塔
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

                    // 右上：说明书
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

            // --- 3) 动态通知层 ---
            VStack(spacing: 10) {
                if let message = transientInstruction {
                    TacticalAlertView(message: message)
                }
                if let skill = activeNotification {
                    SkillFeedbackOverlay(skill: skill)
                }

                if let msg = game.toastMessage {
                    TacticalAlertView(message: msg)
                }
            }
            .padding(.top, 145)
            .allowsHitTesting(false)

            // --- 4) 底部 UI ---
            VStack {
                Spacer()

                HStack(alignment: .bottom) {
                    // --- 1. 左侧：退出按钮 ---
                    // 确保宽度与右侧背包一致，保证中间部分绝对居中
                    Group {
                        HoldToEndButton(holdDuration: 1.5) {
                            if game.isHost {
                                await game.hostEndGame()
                            } else {
                                // ✅ 不允许玩家随意 finish（先稳定体验）
                                await MainActor.run {
                                    triggerInstruction("⛔️ 只有房主可以结束任务")
                                }
//                                game.finishMyGameAndWait()
                            }
                        }
                        // 强制设置成 64x64，与背包按钮对齐
                        .frame(width: 64, height: 64)
                    }
                    .frame(width: 64) // 宽度由 80 -> 64
                    .padding(.leading, 10) // 缩减一点边距
        

                    Spacer()  // <--- 第一个弹簧，将中间推向中心

                    // --- 2. 中间：抓捕条 ---
                    // ✅ 抓捕条：出现条件 = 猎人 + playing + 有候选
                    if game.canAct, let target = captureCandidate,
                        let dist = captureDistance
                    {
                        CaptureBar(
                            state: captureState,
                            targetName: target.displayName,
                            dist: dist,
                            onHold: {
                                guard guardCanAct("👀 你已无法抓捕，正在观战") else {
                                    return
                                }
                               
                                let canRip = dist <= 150
                                
                                if canRip {
                                    targetToRip = target
                                    withAnimation(.spring()) {
                                        showRipUI = true
                                    }
                                } else {
                                    triggerInstruction("⚠️ 需要更靠近才能抓捕（≤150m）")
                                }
                            },
                            onTapLock: {
                                guard guardCanAct("👀 你已无法锁定目标，正在观战") else {
                                    return
                                }
                                lockedTargetId = target.id
                                lockUntil = Date().addingTimeInterval(3.0)
                                refreshCaptureCandidate()
                                UIImpactFeedbackGenerator(style: .light)
                                    .impactOccurred()
                            }
                        )
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                    } else {
                        // 占位符宽度也要同步改为 220
                        Spacer()
                            .frame(width: 220, height: 74)
                            .offset(y: -25)
                        
                    }

                    Spacer()

                    VStack(spacing: 14) {
                        if isBackpackExpanded {
                            ForEach(myItems) { item in
                                Button {
                                    guard guardCanAct("👀 你已无法使用道具，正在观战") else {
                                        return
                                    }
                                    useItem(item)
                                } label: {
                                    Text(item.icon)
                                        .font(.system(size: 26))
                                        .modifier(
                                            GlassButtonStyle(
                                                size: 54,
                                                color: item.color
                                            )
                                        )
                                }
                                .transition(
                                    .move(edge: .bottom)
                                        .combined(with: .scale)
                                        .combined(with: .opacity)
                                )
                            }
                        }

                        Button {
                            guard guardCanAct("👀 你已无法操作背包，正在观战") else { return }

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
                    .frame(width: 64) // 宽度由 80 -> 64
                    .padding(.leading, 10) // 缩减一点边距
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Use Item
    private func useItem(_ item: ItemDef) {
        // ✅✅✅ 新增：行动 gate
        guard guardCanAct("👀 你已无法使用道具，正在观战") else { return }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        triggerInstruction("📡 正在使用：\(item.name)...")

        Task {
            do {
                let result = try await game.useItem(
                    type: item.type,
                    targetUserId: nil,
                    payload: [:]
                )

                if result.ok == false {
                    await MainActor.run {
                        triggerInstruction(
                            "❌ 道具失败：\(result.reason ?? "unknown")"
                        )
                    }
                    return
                }

                await MainActor.run {
                    withAnimation { activeNotification = item }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { activeNotification = nil }
                    }
                    triggerInstruction("✅ 已使用：\(item.name)")
                }
            } catch {
                await MainActor.run {
                    triggerInstruction("❌ 道具使用失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Top instruction
    private func triggerInstruction(_ message: String) {
        guard !message.isEmpty else { return }
        withAnimation(.easeIn(duration: 0.2)) { transientInstruction = nil }
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

    private func effectiveDistance(to coord: CLLocationCoordinate2D) -> Double {
        game.distanceTo(coord)
    }


    // MARK: - Capture candidate selection
    private func refreshCaptureCandidate() {
        if showRipUI || showCaptureOverlay { return }

        guard game.canAct, game.meRole == .hunter, game.phase == .playing else {
            captureState = .idle
            captureCandidate = nil
            captureDistance = nil
            return
        }

        let now = Date()

        // 1) 锁定目标优先
        if let lockedId = lockedTargetId,
            let until = lockUntil,
            now < until,
            let p = game.mapPlayers.first(where: {
                $0.id == lockedId && $0.role == .runner && !$0.isMe
            })
        {
            let d = effectiveDistance(to: p.coordinate)
            captureState = .locked
            captureCandidate = p
            captureDistance = d
            return
        } else {
            if lockUntil != nil, (lockUntil ?? .distantPast) <= now {
                lockedTargetId = nil
                lockUntil = nil
            }
        }

        // 2) 找最近 runner
        let runners = game.mapPlayers.filter { $0.role == .runner && !$0.isMe }
        let nearest =
            runners
            .map { ($0, effectiveDistance(to: $0.coordinate)) }
            .filter { $0.1.isFinite }
            .min(by: { $0.1 < $1.1 })

        guard let (p, d) = nearest else {
            captureState = .idle
            captureCandidate = nil
            captureDistance = nil
            return
        }


        // 3) 正常距离门槛 + 滞回
        let showRadius: Double = 15
        let hideRadius: Double = 18

        if captureCandidate?.id == p.id {
            if d <= hideRadius {
                captureState = .inRange
                captureDistance = d
            } else {
                captureState = .idle
                captureCandidate = nil
                captureDistance = nil
            }
            return
        }

        if d <= showRadius {
            captureState = .inRange
            captureCandidate = p
            captureDistance = d
        } else {
            captureState = .idle
            captureCandidate = nil
            captureDistance = nil
        }
    }

    // MARK: - Overlay Presenter
    // MARK: - Overlay Presenter (supports preemption)
    private func presentOverlay(_ req: GameStore.OverlayRequest) {
        // 1) 如果当前已经有 overlay 在显示：只有更高优先级才允许覆盖
        if showCaptureOverlay {
            if req.priority <= currentOverlayPriority { return }
        }

        // 2) 取消旧的自动关闭任务（避免旧任务把新的 overlay 提前关掉）
        overlayDismissTask?.cancel()
        overlayDismissTask = nil

        // 3) 切换 overlay 内容（用 req.id 强制刷新动画）
        currentOverlayPriority = req.priority
        overlayID = req.id  // ✅ 用 request 的 id，保证“同一 request 只动画一次”
        captureResult = (req.type, req.message)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showCaptureOverlay = true
        }

        // 4) 按 ttl 自动关闭（MainMapView 自己关，不依赖 CaptureOverlayView 的 onDismiss）
        overlayDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(req.ttl * 1_000_000_000))

            // 关动画
            withAnimation(.easeOut(duration: 0.2)) {
                showCaptureOverlay = false
            }

            // 清理优先级
            currentOverlayPriority = -1
        }
    }

    // MARK: - Attempt Tag
    @MainActor
    private func attemptTag(targetId: UUID) async {
        DLog.info("🚀 [Logic] attemptTag START target=\(targetId)")
        withAnimation(.easeInOut(duration: 0.18)) { showRipUI = false }

        // ✅✅✅ 新增：行动 gate（caught/finished 直接挡）
        guard guardCanAct("👀 你已无法抓捕，正在观战") else { return }

        guard game.phase == .playing else {
            DLog.warn("🛑 [Logic] blocked: phase is \(game.phase)")
            triggerInstruction("❌ 只能在行动阶段抓捕")
            return
        }
        guard game.meRole == .hunter else {
            triggerInstruction("❌ 只有猎人可以抓捕")
            return
        }

        do {
            DLog.info("📡 [Logic] Calling RPC...")
            let result = try await game.attemptTag(targetUserId: targetId)
            DLog.info(
                "🧪 attemptTag result ok=\(result.ok) reason=\(result.reason ?? "-") dist=\(result.dist_m ?? -1) radius=\(result.capture_radius_m ?? -1)"
            )
            DLog.info("✅ [Logic] RPC Result: ok=\(result.ok)")
            if result.ok {
                // ✅ 不在这里 presentOverlay：交给 room_events / rooms.ended 统一驱动
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                DLog.warn("⚠️ Capture Failed: \(result.reason ?? "unknown")")
                triggerInstruction(humanizeAttemptTagReason(result))
            }
        } catch {
            DLog.err("🔥 RPC Error: \(error)")
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
        case "target_cloaked": return "🫥 目标隐匿中：试试葡萄雷达，或再贴近一点"

        default:
            return "❌ 抓捕失败：\(r.reason ?? "unknown")"
        }
    }

    // MARK: - Action Gate

    /// 统一 gate：不允许行动时给统一提示 + 反馈
    @MainActor
    private func guardCanAct(_ tip: String = "👀 你已无法行动，正在观战") -> Bool {
        guard game.canAct else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            triggerInstruction(tip)
            return false
        }
        return true
    }

    /// 某些行为只要求“仍在 playing”，不要求 active（例如看说明书/移动镜头）
    @MainActor
    private func guardPlaying(_ tip: String = "⛔️ 当前不在行动阶段") -> Bool {
        guard game.phase == .playing else {
            triggerInstruction(tip)
            return false
        }
        return true
    }

}

//
// MARK: - 你原本 MainMapView.swift 里定义的组件（被整文件替换覆盖了）
//

// MARK: - 战术弹出提醒组件
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
        .transition(
            .asymmetric(
                insertion: .move(edge: .top)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.8)),
                removal: .opacity.combined(with: .scale(scale: 1.1))
            )
        )
    }
}

// MARK: - 技能反馈组件
struct SkillFeedbackOverlay: View {
    let skill: ItemDef
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
        .transition(
            .asymmetric(
                insertion: .move(edge: .top)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.8)),
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
