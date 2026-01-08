//
//  GameStore.swift
//  RunningMan
//
//  ✅ 新版同步层：
//  - Broadcast：高频移动同步（体验层）
//  - Presence：在线成员/断线判定（真在线）
//  - DB：低频落库（裁判/断线重连/反作弊）
//

import CoreLocation
import MapKit
import Observation
import SwiftUI
import Supabase



@MainActor
@Observable
final class GameStore {

    // MARK: - ① Dependencies

    private let locationService: LocationService
    private let routeService: RouteService
    private let roomService = RoomService()
    private let profileService = ProfileService()

    // MARK: - ② External (injected / set by caller)

    var meId: UUID?

    // MARK: - ③ Room Core State

    var roomId: UUID?
    var room: Room?
    var phase: GamePhase = .setup
    var selectedRegion: GameRegion = GameRegion.allCSURegions.first!
    var safeZone: SafeZone?

    /// ✅ room_events 去重（你的 ev.id 是 Int64）
    private var handledRoomEventIds: Set<Int64> = []



    /// ✅ 同步生命周期：只看是否仍在房间内（不要用 phase）
    private(set) var isInRoom: Bool = false

    /// 用于 grace：刚进房间的前 3 秒，不显示离线（等 presence sync）
    private var enteredRoomAt: Date? = nil

    // MARK: - ④ Role Protection

    private var lastLocalRoleChangeTime: Date = .distantPast
    private var roleUpdateTask: Task<Void, Never>?

    // MARK: - ⑤ Realtime Cache (DB 真相 + 广播补充)

    var statesByUserId: [UUID: RoomPlayerState] = [:]
    /// ✅ 玩家首次出现在本地的时间（用于“前 3 秒默认在线”）
    private var firstSeenAtByUserId: [UUID: Date] = [:]

    /// ✅ 进入 lobby 后，前 5秒默认在线
    private let lobbyOnlineGrace: TimeInterval = 5.0


    // MARK: - ⑥ Presence (真在线)

    var presenceOnlineIds: Set<UUID> = []
    
    /// Presence 是否至少 sync 过一次（避免刚进房就误判离线）
    var presenceDidSyncOnce: Bool = false

    /// Sync/Presence 通道是否已连接（断网/重连用）
    var syncChannelConnected: Bool = false


    // MARK: - ⑦ Broadcast 防乱序

    private var lastMoveSeqByUserId: [UUID: Int] = [:]
    private var myMoveSeq: Int = 0
    
    // MARK: - Global Overlay Broadcast (one-shot)

    struct OverlayRequest: Identifiable, Equatable {
        let id = UUID()
        let type: CaptureOverlayView.AnimationType
        let message: String
        let priority: Int         // 大结算 > 被抓 > 抓到一个
        let ttl: TimeInterval     // overlay 展示时间建议 3s
    }

    /// ✅ 全局一次性 Overlay 广播：由 GameStore 产生，MainMapView 消费
    var overlayRequest: OverlayRequest? = nil

    /// ✅ 去重：避免 room_events + room_players 同时触发导致重复弹
    private var lastOverlayFingerprint: String? = nil
    private var lastOverlayAt: Date = .distantPast

    /// ✅ Runner 被抓兜底：检测我自己的 status 边沿变化
    private var lastMePlayableStatus: PlayerStatus? = nil
    
    var amISpectating: Bool {
        guard let meId, let s = statesByUserId[meId] else { return false }
        return s.status == .caught || s.status == .finished
    }

    /// 还能行动：active 才算
    var canAct: Bool {
        guard let meId, let s = statesByUserId[meId] else { return false }
        return phase == .playing && s.status == .active
    }


    @MainActor
    private func emitOverlay(
        _ type: CaptureOverlayView.AnimationType,
        _ message: String,
        priority: Int,
        ttl: TimeInterval = 3.0,
        fingerprint: String
    ) {
        let now = Date()

        // 1) 近时间内同 fingerprint 不重复弹（避免 events + status 双触发）
        if lastOverlayFingerprint == fingerprint, now.timeIntervalSince(lastOverlayAt) < 1.2 {
            return
        }

        // 2) 如果当前 overlayRequest 未被消费，按优先级决定是否覆盖
        if let cur = overlayRequest {
            if priority <= cur.priority { return }
        }

        lastOverlayFingerprint = fingerprint
        lastOverlayAt = now
        overlayRequest = OverlayRequest(type: type, message: message, priority: priority, ttl: ttl)
    }

    // MARK: - ⑧ UI State

    var currentRoute: MKRoute?
    var trackingTargetId: UUID?
    var errorMessage: String?

    // MARK: - ⑨ Timer

    private var gameTimer: Timer?

    // MARK: - ⑩ DB Heartbeat（低频落库）

    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval = 2.0

    // MARK: - ⑪ Broadcast Move（高频移动同步）

    private var broadcastMoveTask: Task<Void, Never>?
    private let broadcastInterval: TimeInterval = 0.10 // 10Hz（推荐 0.08~0.15）

    // MARK: - ⑫ Profile Cache

    var profileCache: [UUID: ProfileService.ProfileInfo] = [:]
    private var fetchingIds: Set<UUID> = []

    // MARK: - ⑬ Computed / Derived

    var isHost: Bool { room?.createdBy == meId }

    var phaseInstruction: String {
        switch phase {
        case .setup:
            return "请选择行动区域并建立代号"
        case .lobby:
            return isHost ? "等待其他特工准备就绪..." : "等待房主开启行动..."
        case .playing:
            return "行动进行中，请保持在安全区内"
        case .gameOver:
            return isHost ? "任务结束。您可以发起再来一局" : "任务结束。请等待房主发起重开"
        }
    }

    var lobbyPlayers: [LobbyPlayerDisplay] {
        let now = Date()

        // 头像缺失就补齐
        let allUserIds = statesByUserId.keys
        let missingIds = allUserIds.filter {
            profileCache[$0] == nil && !fetchingIds.contains($0)
        }
        if !missingIds.isEmpty {
            Task { await fetchMissingProfiles(ids: Array(missingIds)) }
        }

        return statesByUserId.values.map { state in
            let info = profileCache[state.userId]
            let isStale = state.isStale(now: now, threshold: 8.0)

            // ✅ 1) 前 3 秒：只要出现在 statesByUserId，就默认在线
            let firstSeen = firstSeenAtByUserId[state.userId]
            let inGrace = (firstSeen != nil) && (now.timeIntervalSince(firstSeen!) < lobbyOnlineGrace)


            let badge: PresenceBadge = {
                // 1) 前 N 秒：只要出现在 statesByUserId，就默认在线
                if inGrace { return .online }

                // 2) 通道没连上：永远 connecting（不进入 offline）
                guard syncChannelConnected else { return .connecting }

                // 3) 还没真正收到过 presence：connecting（不进入 offline）
                guard presenceDidSyncOnce else { return .connecting }

                // 4) 现在才允许 offline
                return presenceOnlineIds.contains(state.userId) ? .online : .offline
            }()

            return LobbyPlayerDisplay(
                id: state.userId,
                displayName: info?.name ?? "Player \(state.userId.uuidString.prefix(4))",
                role: state.role,
                status: state.status,
                isMe: state.userId == meId,
                badge: badge,
                isStale: isStale
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }


    var toastMessage: String? = nil
    var itemNotification: ItemDef? = nil
    
    
    // MARK: - Init

    init(
        locationService: LocationService = LocationService(),
        routeService: RouteService = RouteService()
    ) {
        self.locationService = locationService
        self.routeService = routeService
    }

    // MARK: - ② UI 派生数据（❗不写入数据库）

    /// ✅ 地图上是否显示某个玩家（只影响 mapPlayers，不影响 statesByUserId 真相）
    /// - finished：永远不显示（你要的“完全消失”）
    /// - playing：只显示 active（仍参与行动）
    /// - 其它 phase：给宽松策略（如果 MainMapView 不会出现于这些阶段，这里只是兜底）
    private func shouldShowOnMap(_ state: RoomPlayerState) -> Bool {
        // finished 永远不显示
        if state.status == .finished { return false }
        // 地图只显示 active
        return state.status == .active
    }


    /// ✅ 统一把 RoomPlayerState -> PlayerDisplay（避免 mapPlayers/me/trackingTarget 重复一坨构造代码）
    /// - 注意：这里不做 shouldShowOnMap 过滤，让调用方决定用途
    private func makePlayerDisplay(from state: RoomPlayerState, now: Date) -> PlayerDisplay? {
        // 没坐标就无法上地图/导航
        guard let coordinate = state.coordinate else { return nil }

        // DB 状态（玩法状态）：ready/active/caught/finished...
        let dbStatus = state.status

        // presence 只负责“在线/离线”展示，不参与玩法状态判断
        let isOnlineByPresence = presenceOnlineIds.contains(state.userId)

        // grace：刚进房间 3 秒内，不显示离线（等 presence sync）
        let inGrace = (enteredRoomAt.map { now.timeIntervalSince($0) < 3.0 } ?? false)

        // 离线只由 presence 决定（grace 期间强制在线）
        let isOffline = inGrace ? false : !isOnlineByPresence

        // stale：定位停更/信号弱（不混进 offline 逻辑，这里仅保留计算点）
        _ = state.isStale(now: now, threshold: 8.0)

        // 头像/昵称缓存
        let cachedInfo = profileCache[state.userId]
        let displayName = cachedInfo?.name ?? "Player \(state.userId.uuidString.prefix(4))"

        // 是否越界（示例：离开安全区就 exposed）
        var exposed = false
        if let zone = safeZone {
            let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let centerLoc = CLLocation(latitude: zone.center.latitude, longitude: zone.center.longitude)
            if userLoc.distance(from: centerLoc) > zone.radius { exposed = true }
        }

        return PlayerDisplay(
            id: state.userId,
            roomId: state.roomId,
            displayName: displayName,
            avatarDownloadURL: cachedInfo?.avatarDownloadURL,
            avatarCacheKey: cachedInfo?.avatarPath,
            role: state.role,
            status: dbStatus,
            coordinate: coordinate,
            lastSeenAt: state.updatedAt,
            isMe: state.userId == meId,
            isOffline: isOffline,
            isExposed: exposed,
            state: state.state   // ✅✅✅ 关键：把 DB json state 带到 UI
        )
    }

    /// ✅ 地图使用的数据源（已过滤 finished；playing 时只显示 active）
    /// - 这是“地图视图专用列表”，不要拿它当真相（真相永远是 statesByUserId）
    var mapPlayers: [PlayerDisplay] {
        let now = Date()

        // 头像/昵称缺失就异步补齐（不阻塞 UI）
        let allUserIds = statesByUserId.keys
        let missingIds = allUserIds.filter { id in
            profileCache[id] == nil && !fetchingIds.contains(id)
        }
        if !missingIds.isEmpty {
            Task { await fetchMissingProfiles(ids: Array(missingIds)) }
        }

        return statesByUserId.values
            .filter(shouldShowOnMap)
            .filter { st in
                // ✅ 只对猎人隐藏 cloaked runner
                !isCloakedAndHiddenForHunter(st, now: now)
            }
            .compactMap { makePlayerDisplay(from: $0, now: now) }
            .sorted { $0.displayName < $1.displayName }

    }

    /// ✅ 我自己的 PlayerDisplay（不依赖 mapPlayers）
    /// - 关键点：即使自己 finished 被 mapPlayers 过滤，me 也不会变 nil（避免 UI/HUD 炸）
    /// - 这里用 statesByUserId 真相构造
    var me: PlayerDisplay? {
        guard let meId, let state = statesByUserId[meId] else { return nil }
        return makePlayerDisplay(from: state, now: Date())
    }

    /// ✅ 当前导航目标的 PlayerDisplay（不依赖 mapPlayers）
    /// - 关键点：即使目标玩家 finished 从地图消失，trackingTarget 仍能拿到（方便你做“目标已退出/已结束”的 UI 提示）
    /// - 如果你希望“finished 目标直接丢失导航”，可以在这里额外判断并 return nil
    var trackingTarget: PlayerDisplay? {
        guard let trackingTargetId, let state = statesByUserId[trackingTargetId] else { return nil }
        return makePlayerDisplay(from: state, now: Date())
    }

    /// ✅ 目标玩家的原始 state（真相层）
    /// - 给逻辑判断用：比如 status == .finished / .caught 等
    var trackingTargetState: RoomPlayerState? {
        guard let trackingTargetId else { return nil }
        return statesByUserId[trackingTargetId]
    }

    // MARK: - ③ UI 可绑定入口（Picker）

    /// ✅ 我自己的 state（可读写）
    /// - 用于本地 Picker/Role 编辑写回 statesByUserId
    private var meState: RoomPlayerState? {
        get {
            guard let meId else { return nil }
            return statesByUserId[meId]
        }
        set {
            guard let meId else { return }
            if let newValue {
                statesByUserId[meId] = newValue
            } else {
                statesByUserId.removeValue(forKey: meId)
            }
        }
    }

    /// ✅ 角色绑定入口（依赖可写 meState）
    /// - 注意：这里读写的是 statesByUserId 真相，不受 mapPlayers 过滤影响
    var meRole: GameRole {
        get { meState?.role ?? .runner }
        set {
            var s = meState ?? makePlaceholderMeState(defaultRole: newValue)
            s.role = newValue
            meState = s
        }
    }

    // MARK: - ④ Setup 生命周期

    func onSetupAppear() {
        locationService.requestPermission()
        locationService.start()
        recommendNearestRegionIfPossible()
    }

    func recommendNearestRegionIfPossible() {
        guard phase == .setup else { return }
        guard let user = locationService.currentLocation else { return }

        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)

        if let nearest = GameRegion.allCSURegions.min(by: { a, b in
            userLoc.distance(from: CLLocation(latitude: a.center.latitude, longitude: a.center.longitude))
            < userLoc.distance(from: CLLocation(latitude: b.center.latitude, longitude: b.center.longitude))
        }) {
            selectedRegion = nearest
        }
    }


    // MARK: - ⑥ 安全区缩圈

    private func startZoneShrinking() {
        stopZoneShrinking()

        let tick: TimeInterval = 1.0
        let shrinkPerTick: CLLocationDistance = 3

        gameTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                guard var zone = self.safeZone else { return }
                guard zone.radius > 100 else { return }

                zone.radius -= shrinkPerTick
                withAnimation(.easeInOut(duration: tick)) {
                    self.safeZone = zone
                }
            }
        }
    }

    private func stopZoneShrinking() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    // MARK: - ⑦ Navigation

    func navigate(to userId: UUID) async {
        trackingTargetId = userId

        // ✅ 用真相层找（statesByUserId），不要用 mapPlayers（会过滤）
        guard let state = statesByUserId[userId],
                shouldShowOnMap(state),
                let coordinate = state.coordinate else { return }

        do {
            let route = try await routeService.walkingRoute(to: coordinate)
            withAnimation(.easeInOut) { currentRoute = route }
        } catch {
            errorMessage = "无法规划路线：\(error.localizedDescription)"
        }
    }

    func cancelNavigation() {
        withAnimation(.easeInOut) {
            currentRoute = nil
            trackingTargetId = nil
        }
    }

    // MARK: - ⑧ Realtime 输入口（Supabase）

    func applyRemove(userId: UUID) {
        statesByUserId.removeValue(forKey: userId)
        lastMoveSeqByUserId.removeValue(forKey: userId)
    }

    /// ✅ rooms 更新入口（由 RoomService rooms realtime 回调触发）
    func applyRoomUpdate(_ room: Room) {
        DLog.info("🏠 applyRoomUpdate status=\(room.status.rawValue)")

        self.room = room

        // Region Sync
        if let rid = room.regionId, selectedRegion.id != rid {
            if let matched = GameRegion.allCSURegions.first(where: { $0.id == rid }) {
                DLog.info("🗺️ [GameStore] 收到远程区域更新: \(matched.name)")
                withAnimation(.easeInOut(duration: 1.0)) {
                    self.selectedRegion = matched
                }
            } else {
                DLog.warn("⚠️ [GameStore] 收到未知区域ID: \(rid)")
            }
        }

        switch room.status {
        case .waiting:
            stopZoneShrinking()
            cancelNavigation()
            if phase != .lobby {
                withAnimation(.easeInOut) { phase = .lobby }
                // 回大厅：状态重置 ready（仅玩法状态）
                if let meId,
                   let my = statesByUserId[meId],
                   my.status == .active {
                    updateMyStatus(.ready)
                }

            }

        case .playing:
            if safeZone == nil {
                safeZone = SafeZone(center: selectedRegion.center, radius: selectedRegion.initialRadius)
            }
            locationService.start()
            startZoneShrinking()

            if phase != .playing {
                withAnimation(.easeInOut) { phase = .playing }
                // 游戏开始：ready -> active（不覆盖 caught）
                if let meId, let myState = statesByUserId[meId], myState.status == .ready {
                    DLog.info("🚀 游戏开始，状态切换 ready -> active")
                    updateMyStatus(.active)
                }
            }

        case .ended:
              stopZoneShrinking()
              cancelNavigation()

              // ✅✅✅ 最佳体验：overlay 播完再切 gameOver（用 ttl 驱动）
              // 1) 只在“第一次进入 ended”时发 overlay & 安排延迟切换（避免重复触发）
              if phase != .gameOver {
                  let ttl: TimeInterval = 3.2

                  if meRole == .hunter {
                      emitOverlay(
                          .gameVictory,
                          "任务结束\n猎人胜利 ✅",
                          priority: 100,
                          ttl: ttl,
                          fingerprint: "rooms_ended:\(room.id.uuidString):hunter"
                      )
                  } else {
                      emitOverlay(
                          .gameDefeat,
                          "任务结束\n逃跑者失败 ❌",
                          priority: 100,
                          ttl: ttl,
                          fingerprint: "rooms_ended:\(room.id.uuidString):runner"
                      )
                  }

                  // 2) ✅ 按 ttl 延迟切 gameOver，让 overlay 一定可见且尽量播完
                  Task { @MainActor [weak self] in
                      guard let self else { return }

                      // ⚠️ delay 至少 0.35s，避免“UI 还没渲染一帧就切走”
                      let delay = max(0.35, ttl - 0.2)
                      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                      // ✅ 如果中途房间被 close/leave/reset 了，就别切了
                      guard self.roomId == room.id else { return }

                      withAnimation(.easeInOut) {
                          self.phase = .gameOver
                      }
                  }
              } else {
                  // 已经 gameOver 了，不重复安排 Task
                  DLog.info("🏁 applyRoomUpdate ended: already in gameOver, skip overlay/transition")
              }

        case .closed:
            stopZoneShrinking()
            cancelNavigation()
            resetRoomState()
            withAnimation(.easeInOut) { phase = .setup }
        }
    }

    /// ✅ 更新自己的玩法状态（ready/active/caught）
    func updateMyStatus(_ newStatus: PlayerStatus) {
        guard newStatus.isDBPlayableStatus else {
              DLog.warn("Refuse to write offline into DB status")
              return
        }
        guard let roomId, let meId else { return }

        // 本地乐观更新
        if var s = statesByUserId[meId] {
            s.status = newStatus
            statesByUserId[meId] = s
        }

        // 推送 DB（低频位置依然会写，但状态改变必须立即写）
        Task {
            try? await roomService.upsertMyState(
                roomId: roomId,
                meId: meId,
                role: meRole.rawValue,
                status: newStatus.rawValue,
                lat: locationService.currentLocation?.latitude,
                lng: locationService.currentLocation?.longitude
            )
        }
    }

  
    /// ✅ 结束本局参与（投降/退出行动）：留在 MainMapView 观战，不切 phase
    func finishMyGameAndWait() {
        // 0) 必须在房间里
        guard isInRoom else { return }
        guard meState?.status != .finished else { return } // ✅ 已经 finished 就不重复做

        // 1) 停止所有“行动同步”
        stopBroadcastMove()
        stopHeartbeat()

        // 2) 上报玩法状态（DB）
        updateMyStatus(.finished)


        DLog.info("🏁 finishMyGameAndWait: stop move+heartbeat, status=finished (phase unchanged)")

    }



    // MARK: - ⑨ Broadcast Move 应用（体验层）

    /// ✅ 接收别人的高频坐标（Broadcast）
    /// - 体验层只更新坐标/时间；绝不改变 role/status（DB 真相优先）
    /// - caught/finished 的人忽略广播，避免“复活”
    func applyRemoteMove(userId: UUID, lat: Double, lng: Double, ts: Date, seq: Int) {
        if userId == meId { return }

        let lastSeq = lastMoveSeqByUserId[userId] ?? -1
        if seq <= lastSeq { return }
        lastMoveSeqByUserId[userId] = seq

        guard let rid = self.roomId else { return }

        // ✅ 如果已有 state，永远不改 role/status
        if var existing = statesByUserId[userId] {

            // ✅ caught/finished 不吃广播，避免地图复活、重复抓
            if existing.status != .active { return }

            existing.lat = lat
            existing.lng = lng
            existing.updatedAt = ts
            statesByUserId[userId] = existing
            return
        }

        // ✅ 本地完全没见过：建占位（但这只是“坐标缓存”，以后 DB upsert 会覆盖）
        if firstSeenAtByUserId[userId] == nil {
            firstSeenAtByUserId[userId] = Date()
        }

        statesByUserId[userId] = RoomPlayerState(
            roomId: rid,
            userId: userId,
            role: .runner,         // 默认值无所谓，后续 DB upsert 会纠正
            status: .active,       // 这里只是占位；但一旦 DB 告诉我们 caught，就会被锁死不再吃广播
            lat: lat,
            lng: lng,
            updatedAt: ts,
            joinedAt: nil
        )
    }

    // MARK: - ⑩ Reset

    func resetRoomState() {
        roomId = nil
        room = nil
        phase = .setup
        safeZone = nil
        stopZoneShrinking()

        statesByUserId.removeAll()
        presenceOnlineIds.removeAll()
        lastMoveSeqByUserId.removeAll()
        myMoveSeq = 0

        currentRoute = nil
        trackingTargetId = nil
        errorMessage = nil
        firstSeenAtByUserId.removeAll()
    }

    // MARK: - ⑪ Helpers

    private func makePlaceholderMeState(defaultRole: GameRole) -> RoomPlayerState {
        let id = meId ?? UUID()
        let room = roomId ?? UUID()

        return RoomPlayerState(
            roomId: room,
            userId: id,
            role: defaultRole,
            status: .active,
            lat: nil,
            lng: nil,
            updatedAt: Date(),
            joinedAt: nil,
        )
    }

    // MARK: - ⑫ DB 低频落库（给裁判用）

    private func startHeartbeat() {
        stopHeartbeat()

        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            DLog.ok("DB heartbeat started interval=\(self.heartbeatInterval)s")

            defer { DLog.warn("DB heartbeat ended") }

            while !Task.isCancelled {
                // ✅ 只要不在房间，立即退出（不要 continue 空转）
                guard self.isInRoom else {
                    DLog.warn("DB heartbeat stopped: isInRoom=false")
                    break
                }

                // ✅ sleep
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000)
                    )
                } catch {
                    DLog.warn("DB heartbeat sleep cancelled")
                    break
                }

                // ✅ sleep 后再检查一次，避免 leaveRoom() 过程中又跑一轮
                guard self.isInRoom else {
                    DLog.warn("DB heartbeat stopped after sleep: isInRoom=false")
                    break
                }

                guard let roomId = self.roomId, let meId = self.meId else {
                    DLog.warn("heartbeat: missing roomId/meId (will retry)")
                    continue
                }

                guard let loc = self.locationService.currentLocation else {
                    DLog.warn("heartbeat: no location yet")
                    continue
                }

                // ✅ 低频落库：位置 + updated_at（role/status 可带）
                let myCurrentRole = self.meRole.rawValue
                let myCurrentStatus = self.statesByUserId[meId]?.status.rawValue
                    ?? PlayerStatus.active.rawValue

                do {
                    try await self.roomService.upsertMyState(
                        roomId: roomId,
                        meId: meId,
                        role: myCurrentRole,
                        status: myCurrentStatus,
                        lat: loc.latitude,
                        lng: loc.longitude
                    )
                } catch {
                    // ❗不要因此退出，继续下一轮
                    DLog.warn("heartbeat upsert failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopHeartbeat() {
        guard let task = heartbeatTask else { return }
        task.cancel()
        heartbeatTask = nil
        Task { await Task.yield() } // ✅ 让 cancel 更快生效（可选但推荐）
    }

    // MARK: - ⑬ Broadcast 高频移动同步

    private func startBroadcastMove() {
        stopBroadcastMove()

        broadcastMoveTask = Task { [weak self] in
            guard let self else { return }
            DLog.ok("Broadcast move started interval=\(self.broadcastInterval)s")

            defer { DLog.warn("Broadcast move ended") }

            while !Task.isCancelled {
                // ✅ 不在房间就退出
                guard self.isInRoom else {
                    DLog.warn("Broadcast move stopped: isInRoom=false")
                    break
                }

                // ✅ sleep
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(self.broadcastInterval * 1_000_000_000)
                    )
                } catch {
                    DLog.warn("Broadcast move sleep cancelled")
                    break
                }

                // ✅ sleep 后再检查一次
                guard self.isInRoom else {
                    DLog.warn("Broadcast move stopped after sleep: isInRoom=false")
                    break
                }

                guard let meId = self.meId else {
                    DLog.warn("broadcast: missing meId (will retry)")
                    continue
                }
                guard self.roomId != nil else {
                    DLog.warn("broadcast: missing roomId (will retry)")
                    continue
                }
                guard let loc = self.locationService.currentLocation else {
                    // 高频任务这里不打 warn，避免刷屏
                    continue
                }

                self.myMoveSeq += 1

                await self.roomService.broadcastMove(
                    meId: meId,
                    lat: loc.latitude,
                    lng: loc.longitude,
                    seq: self.myMoveSeq
                )
            }
        }
    }

    private func stopBroadcastMove() {
        guard let task = broadcastMoveTask else { return }
        task.cancel()
        broadcastMoveTask = nil
        Task { await Task.yield() } // ✅ 让 cancel 更快生效（可选但推荐）
    }

    // MARK: - ⑭ Room Flow（join / leave / host ops / role）

    func joinRoom(roomId: UUID) async {
        guard let meId else {
            errorMessage = "未登录"
            return
        }

        locationService.requestPermission()
        locationService.start()

        self.roomId = roomId
        errorMessage = nil
        
        // ✅✅✅【新增】本地先登记自己：Lobby 立刻有 1 人，不等 snapshot
           if statesByUserId[meId] == nil {
               // ✅ 这里就是你找不到的位置：第一次看到自己就记时间（用于 lobby 3 秒默认在线）
                if firstSeenAtByUserId[meId] == nil {
                    firstSeenAtByUserId[meId] = Date()
                }
               statesByUserId[meId] = RoomPlayerState(
                   roomId: roomId,
                   userId: meId,
                   role: meRole,
                   status: .ready,          // 进 lobby 默认 ready
                   lat: nil,
                   lng: nil,
                   updatedAt: Date(),
                   joinedAt: Date()
               )
           }

        // 1) 订阅 room_players changes
        roomService.setRoomPlayersCallbacks(
            onUpsert: { [weak self] state in
                Task { @MainActor in self?.applyUpsert(state) }
            },
            onDelete: { [weak self] userId in
                Task { @MainActor in self?.applyRemove(userId: userId) }
            }
        )

        // 2) 订阅 rooms changes
        roomService.setRoomCallback(onUpdate: { [weak self] room in
            Task { @MainActor in self?.applyRoomUpdate(room) }
        })

        // 3) ✅ 同步层 callbacks（Broadcast + Presence）
        roomService.setSyncCallbacks(
            onMove: { [weak self] uid, lat, lng, ts, seq in
                Task { @MainActor in
                    self?.applyRemoteMove(userId: uid, lat: lat, lng: lng, ts: ts, seq: seq)
                }
            },
            onPresenceSync: { [weak self] online in
                Task { @MainActor in
                    guard let self else { return }
                    self.presenceOnlineIds = online
                    // ✅ 只有“真的收到一次 presence 回调”才算 didSyncOnce
                    if self.presenceDidSyncOnce == false {
                        self.presenceDidSyncOnce = true
                    }
                }
            },
            onSyncStatus: { [weak self] connected in
                Task { @MainActor in
                    self?.syncChannelConnected = connected
                    // 可选：断线时也把 didSyncOnce 复位（更符合“未知=connecting”）
                    if connected == false {
                        self?.presenceDidSyncOnce = false
                    }
                }
            }
        )

        
        // GameStore.joinRoom(roomId:) 里加上（和 rooms/players 同级）
        roomService.setRoomEventCallback { [weak self] ev in
            Task { @MainActor in
                self?.applyRoomEvent(ev)
            }
        }
      


        do {
            // ✅ rooms realtime：先订阅
            try await roomService.subscribeRoom(roomId: roomId)
            try await roomService.subscribeRoomEvents(roomId: roomId)
            // ✅ 到这里为止，才算真正进入房间
            self.isInRoom = true

            // ✅ rooms snapshot
            let r = try await roomService.fetchRoom(roomId: roomId)
            applyRoomUpdate(r)

            // ✅ players realtime + snapshot + upsert me
            let snapshot = try await roomService.joinRoom(
                roomId: roomId,
                meId: meId,
                initialRole: meRole.rawValue,
                initialStatus: PlayerStatus.ready.rawValue
            )
            snapshot.forEach { applyUpsert($0) }

            // ✅ 同步层：Presence + Broadcast
            try await roomService.subscribeSync(roomId: roomId, meId: meId)
            
            self.enteredRoomAt = Date()

            // ✅ 启动：低频落库 + 高频广播
            startHeartbeat()
            startBroadcastMove()

            DLog.ok("joinRoom OK snapshot=\(snapshot.count)")
        } catch {
            errorMessage = error.localizedDescription
            DLog.err("joinRoom failed: \(error.localizedDescription)")
        }
    }
    
    
    // MARK: - room_events realtime 入口（统一驱动 toast + overlayRequest）

    @MainActor
    private func applyRoomEvent(_ ev: RoomEvent) {
        DLog.info("📨 room_event id=\(ev.id) type=\(ev.type) payload=\(String(describing: ev.payload))")

        // 0) 只处理我们关心的事件类型
        guard ["item_used", "shield_blocked", "tag_success"].contains(ev.type) else { return }

        // 1) 去重（避免重复 insert / 重连补发 / 同一事件多次回调）
        if handledRoomEventIds.contains(ev.id) { return }
        handledRoomEventIds.insert(ev.id)

        // 2) ✅ 过滤自己：只对非抓捕事件过滤
        //    - item_used / shield_blocked：自己触发没必要 toast（避免刷屏）
        //    - tag_success：绝对不能过滤！否则猎人收不到自己抓到人的“盖章”
        if ev.type != "tag_success", let actor = ev.actor, actor == meId {
            return
        }

        // 3) actorName / roleTag
        let actorName: String = {
            guard let actor = ev.actor else { return "有人" }
            if let info = profileCache[actor], !info.name.isEmpty { return info.name }
            return String(actor.uuidString.prefix(4)).uppercased()
        }()

        let actorRoleTag: String = {
            guard let actor = ev.actor else { return "" }
            switch statesByUserId[actor]?.role {
            case .some(.hunter): return "猎人"
            case .some(.runner): return "逃跑者"
            default: return ""
            }
        }()

        let roleSuffix = actorRoleTag.isEmpty ? "" : "（\(actorRoleTag)）"

        // 4) icon
        let icon: String = {
            switch ev.type {
            case "item_used": return "🧰"
            case "shield_blocked": return "🛡️"
            case "tag_success": return "✅"
            default: return "ℹ️"
            }
        }()

        // 5) toast 自动清理
        func autoClearToast(after seconds: Double = 3.0) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                toastMessage = nil
            }
        }

        switch ev.type {

        // =========================================================
        // item_used：只 toast（不出盖章）
        // =========================================================
        case "item_used":
            guard let s = ev.payloadString("item_type"),
                  let t = ItemType(rawValue: s),
                  let def = ItemDef.byType[t]
            else {
                DLog.warn("⚠️ item_used but payload item_type decode failed")
                return
            }

            toastMessage = "\(icon) \(actorName)\(roleSuffix) · 使用：\(def.name)"
            autoClearToast(after: 3.0)

        // =========================================================
        // shield_blocked：只 toast（不出盖章）
        // =========================================================
        case "shield_blocked":
            let left = ev.payloadInt("shield_left") ?? ev.payloadInt("remaining_shield")
            let dist = ev.payloadDouble("dist_m")

            var msg = "\(icon) \(actorName)\(roleSuffix) · 护盾抵挡"
            if let dist { msg += "（\(String(format: "%.1f", dist))m）" }
            if let left { msg += "｜剩余 \(left)" }

            toastMessage = msg
            autoClearToast(after: 3.0)

        // =========================================================
        // tag_success：抓捕事件（toast + 统一 overlayRequest）
        // =========================================================
        case "tag_success":
            let dist = ev.payloadDouble("dist_m")
            let remaining = ev.payloadInt("remaining_runners")

            let targetName: String = {
                guard let target = ev.target else { return "目标" }
                if let info = profileCache[target], !info.name.isEmpty { return info.name }
                return String(target.uuidString.prefix(4)).uppercased()
            }()

            var msg = "\(icon) \(actorName)\(roleSuffix) · 抓到 \(targetName)"
            if let dist { msg += "｜\(String(format: "%.1f", dist))m" }
            if let remaining { msg += "｜剩余 \(remaining)" }

            // ✅ A) 我是 target：runner 盖章（最高优先级之一）
            if let target = ev.target, target == meId {
                emitOverlay(
                    .runnerBusted,
                    "你被猎人抓获！",
                    priority: 90,
                    ttl: 3.0,
                    fingerprint: "busted_event:\(ev.id)"
                )
            }

            // ✅ B) 我是 actor：hunter 抓到一个 盖章
            //    注意：上面我们已经确保 tag_success 不会被 actor==meId 过滤掉
            if let actor = ev.actor, actor == meId {
                let distText = dist.map { String(format: "%.1f", $0) } ?? "-"
                let remText = remaining.map { "\($0)" } ?? "-"
                emitOverlay(
                    .hunterCaughtOne,
                    "抓捕成功！\n距离 \(distText) 米｜剩余目标 \(remText)",
                    priority: 60,
                    ttl: 3.0,
                    fingerprint: "hunter_caught_one_event:\(ev.id)"
                )
            }

            // ✅ C) remaining==0：给所有人一个“结算预告盖章”
            //    rooms.status=ended 之后还会再来一次最终盖章（你在 applyRoomUpdate 里做的）
            if let r = remaining, r == 0 {
                if meRole == .hunter {
                    emitOverlay(
                        .gameVictory,
                        "全员逮捕归案！\n猎人阵营大获全胜 🎉",
                        priority: 100,
                        ttl: 3.2,
                        fingerprint: "game_over_preview_event:\(ev.id):hunter"
                    )
                } else {
                    emitOverlay(
                        .gameDefeat,
                        "全员被捕！\n逃跑者阵营失败 ☠️",
                        priority: 100,
                        ttl: 3.2,
                        fingerprint: "game_over_preview_event:\(ev.id):runner"
                    )
                }
            }

            // toast（可选）
            toastMessage = msg
            autoClearToast(after: 3.0)

        default:
            return
        }
    }





    func leaveRoom() async {
        await cleanupAndResetLocal()
        DLog.ok("leaveRoom done")
    }

    // MARK: - Room Create / Host Ops

    func createRoomAndJoin() async {
        await createRoomAndJoin(regionId: self.selectedRegion.id)
    }

    func createRoomAndJoin(regionId: UUID?) async {
        guard let meId else {
            errorMessage = "未登录"
            return
        }

        do {
            let newRoomId = try await roomService.createRoom(
                createdBy: meId,
                status: "waiting",
                regionId: regionId,
                rule: [:]
            )
            await joinRoom(roomId: newRoomId)
        } catch {
            errorMessage = error.localizedDescription
            DLog.err("createRoomAndJoin failed: \(error.localizedDescription)")
        }
    }

    func lockSelectedRegion() async {
        guard isHost else {
            errorMessage = "只有房主可以锁定区域"
            return
        }
        guard let roomId else { return }

        do {
            try await roomService.lockRoomRegion(roomId: roomId, regionId: selectedRegion.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canStartGame: Bool { roomId != nil }

    func startRoomGame() async {
        guard isHost else { errorMessage = "只有房主可以开始"; return }
        guard let roomId else { errorMessage = "roomId 为空"; return }
        guard canStartGame else { errorMessage = "未进入房间"; return }
        
        DLog.info("🎮 startRoomGame tapped roomId=\(roomId)")
          do {
              try await roomService.startGame(roomId: roomId)
              DLog.ok("🎮 start_game RPC returned OK")
              // 这里不需要手动 phase = .playing
              // rooms realtime 会推 room.status=playing -> applyRoomUpdate 会切
          } catch {
              errorMessage = "start_game 失败：\(error.localizedDescription)"
              DLog.err("🎮 start_game RPC failed: \(error)")
          }
    }
    
    func closeRoom() async {
        // ✅ 最关键：一进来就打栈（谁调用的一眼看到）
        DLog.err("🧹 closeRoom CALLED stack=\n\(Thread.callStackSymbols.joined(separator: "\n"))")

        guard isHost else {
            errorMessage = "只有房主可以关闭房间"
            DLog.warn("🧹 closeRoom blocked: not host")
            return
        }
        guard let roomId else {
            errorMessage = "roomId 为空"
            DLog.err("🧹 closeRoom blocked: roomId nil")
            return
        }

        DLog.info("🧹 closeRoom tapped roomId=\(roomId)")

        do {
            try await roomService.closeRoom(roomId: roomId)
            DLog.ok("🧹 close_room RPC returned OK")
            // rooms realtime 会推 status=closed -> applyRoomUpdate 会 resetRoomState + phase=.setup
        } catch {
            errorMessage = "close_room 失败：\(error.localizedDescription)"
            DLog.err("🧹 close_room RPC failed: \(error)")
        }
    }
    

    
    private func cleanupAndResetLocal() async {
        // 1️⃣ 第一时间切断一切循环
        self.isInRoom = false

        // 2️⃣ 停后台任务
        stopHeartbeat()
        stopBroadcastMove()

        // 3️⃣ 取消所有订阅（不涉及 DB）
        await roomService.leaveRoom()

        // 4️⃣ 本地彻底回初始态
        resetRoomState()
    }


    func exitGame() async {
        if isHost {
            await closeRoom()              // 裁判动作（关房）
            await cleanupAndResetLocal()   // 本端兜底（不等 realtime）
        } else {
            await leaveRoom()
        }
    }


    // MARK: - Role update (保护盾)

    func pushMyRoleToServer() async {
        guard let roomId, let meId else { return }
        do {
            // ✅ role 改动：即时推一次即可，不需要高频
            try await roomService.upsertMyState(
                roomId: roomId,
                meId: meId,
                role: meRole.rawValue,
                status: (statesByUserId[meId]?.status.rawValue ?? "active"),
                lat: nil,
                lng: nil
            )
        } catch {
            DLog.warn("pushMyRoleToServer failed: \(error.localizedDescription)")
        }
    }

    
    func updateRole(to newRole: GameRole) {
        lastLocalRoleChangeTime = Date()

        if let meId, var myState = statesByUserId[meId] {
            myState.role = newRole
            statesByUserId[meId] = myState
        } else {
            meRole = newRole
        }

        roleUpdateTask?.cancel()
        roleUpdateTask = Task {
            do {
                try await Task.sleep(for: .seconds(0.6))
                if Task.isCancelled { return }
                await pushMyRoleToServer()
            } catch {}
        }
    }

    // MARK: - room_players upsert 入口（DB 真相层）
    // 作用：更新 statesByUserId + runner 被抓“兜底检测”
    // 注意：兜底检测必须放在任何 return 之前，否则会被 role merge 保护期吃掉

    func applyUpsert(_ state: RoomPlayerState) {
        // ✅ 记录首次出现时间（只记录一次）
        if firstSeenAtByUserId[state.userId] == nil {
            firstSeenAtByUserId[state.userId] = Date()
        }

        // ✅ Runner busted fallback（兜底）：检测“我”的 status 边沿变化 active/ready -> caught
        // 放最前面：避免下面 role merge 的 return 把逻辑吃掉
        if state.userId == meId {
            let prev = lastMePlayableStatus
            lastMePlayableStatus = state.status

            if state.status == .caught, prev != .caught {
                emitOverlay(
                    .runnerBusted,
                    "你被猎人抓获！",
                    priority: 80,          // 比 hunterCaughtOne 高；比最终结算低
                    ttl: 3.0,
                    fingerprint: "busted_status:\(state.userId.uuidString)"
                )
            }
        }

        // ✅ 我自己：role 保护期内，保留本地 role（避免网络回写把你刚切换的角色又覆盖掉）
        if state.userId == meId {
            if Date().timeIntervalSince(lastLocalRoleChangeTime) < 2.0,
               let localState = statesByUserId[state.userId] {
                var merged = state
                merged.role = localState.role
                statesByUserId[state.userId] = merged
                return
            }
        }

        // 默认：直接写入真相缓存
        statesByUserId[state.userId] = state
    }

    // MARK: - Game Actions
    
    private func stateDate(_ s: RoomPlayerState, key: String) -> Date? {
        // state: JSONObject? = [String: AnyJSON]
        guard let raw = s.state?[key]?.stringValue else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func isCloakedAndHiddenForHunter(_ target: RoomPlayerState, now: Date) -> Bool {
        guard phase == .playing else { return false }
        guard meRole == .hunter else { return false }
        guard target.role == .runner, target.status == .active else { return false }

        let cloakUntil = stateDate(target, key: "cloak_until")
        guard let cloakUntil, now < cloakUntil else { return false }

        let revealUntil = stateDate(target, key: "reveal_until")
        if let revealUntil, now < revealUntil {
            return false // ✅ 已揭露：可见
        }
        return true // ✅ cloaked 且未揭露：对猎人隐藏
    }


    func hostEndGame() async {
        guard isHost, let roomId else { return }
        do {
            try await roomService.updateRoomStatus(
                roomId: roomId,
                status: RoomStatus.ended.rawValue,
                winner: nil
            )
        } catch {
            errorMessage = "结束游戏失败: \(error.localizedDescription)"
        }
    }

    func hostRematch() async {
        guard isHost, let roomId else { return }
        do {
            try await roomService.updateRoomStatus(
                roomId: roomId,
                status: RoomStatus.waiting.rawValue
            )
        } catch {
            errorMessage = "发起重开失败: \(error.localizedDescription)"
        }
    }

    func attemptTag(targetUserId: UUID) async throws -> AttemptTagResult {
        guard let roomId else {
            throw NSError(domain: "GameStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "roomId nil"])
        }
        return try await roomService.attemptTag(roomId: roomId, targetUserId: targetUserId)
    }
    
    

    // MARK: - ⑮ Profile load

    private func fetchMissingProfiles(ids: [UUID]) async {
        for id in ids { fetchingIds.insert(id) }

        let newProfiles = await profileService.fetchProfilesAndSignAvatars(ids: ids)
        for (uid, info) in newProfiles { self.profileCache[uid] = info }

        for id in ids { fetchingIds.remove(id) }
    }

    // MARK: - ⑯ Utils

    func distanceTo(_ targetCoordinate: CLLocationCoordinate2D) -> Double {
        guard let myLoc = locationService.currentLocation else { return 999_999 }
        let p1 = CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude)
        let p2 = CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
        return p1.distance(from: p2)
    }
}

// MARK: - LobbyPlayerDisplay

struct LobbyPlayerDisplay: Identifiable {
    let id: UUID
    let displayName: String
    let role: GameRole
    let status: PlayerStatus
    let isMe: Bool
    let badge: PresenceBadge
    let isStale: Bool
}

enum PresenceBadge {
    case connecting
    case online
    case offline
}

@MainActor
extension GameStore {
    func useItem(
        type: ItemType,
        targetUserId: UUID? = nil,
        payload: [String: AnyJSON] = [:]
    ) async throws -> UseItemResult {

        guard let roomId = self.roomId else {
            throw RoomService.RoomServiceError.missingRoomId
        }

        return try await roomService.useItem(
            roomId: roomId,
            itemType: type,
            targetUserId: targetUserId,
            payload: payload
        )
    }
}


