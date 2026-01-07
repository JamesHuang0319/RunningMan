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

    /// ✅ 同步生命周期：只看是否仍在房间内（不要用 phase）
    private(set) var isInRoom: Bool = false

    /// 用于 grace：刚进房间的前 3 秒，不显示离线（等 presence sync）
    private var enteredRoomAt: Date? = nil

    // MARK: - ④ Role Protection

    private var lastLocalRoleChangeTime: Date = .distantPast
    private var roleUpdateTask: Task<Void, Never>?

    // MARK: - ⑤ Realtime Cache (DB 真相 + 广播补充)

    var statesByUserId: [UUID: RoomPlayerState] = [:]

    // MARK: - ⑥ Presence (真在线)

    var presenceOnlineIds: Set<UUID> = []
    
    /// Presence 是否至少 sync 过一次（避免刚进房就误判离线）
    var presenceDidSyncOnce: Bool = false

    /// Sync/Presence 通道是否已连接（断网/重连用）
    var syncChannelConnected: Bool = false


    // MARK: - ⑦ Broadcast 防乱序

    private var lastMoveSeqByUserId: [UUID: Int] = [:]
    private var myMoveSeq: Int = 0

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

            // 是否 stale（DB 坐标停更）
            let isStale = state.isStale(now: now, threshold: 8.0)

            // ✅ 计算 PresenceBadge（核心）
            let badge: PresenceBadge = {
                // 1) 还没拿到一次 presence sync：一律显示“连接中”
                //    （避免刚进房就把所有人标离线）
                if !presenceDidSyncOnce {
                    return .connecting
                }

                // 2) 如果你未来把 channel 状态回调出来：
                //    断网/重连时把 syncChannelConnected=false
                if !syncChannelConnected {
                    return .connecting
                }

                // 3) 已经 sync + 连接正常：用 onlineIds 判定在线/离线
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
            isExposed: exposed
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
            .filter(shouldShowOnMap)                     // ✅ 只在这里做“地图显示规则”
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

        let tick: TimeInterval = 0.5
        let shrinkPerTick: CLLocationDistance = 5

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
            if phase != .gameOver {
                withAnimation(.easeInOut) { phase = .gameOver }
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

    /// ✅ 普通玩家：结束本局参与，进入 GameOver 等待（不离房）
    /// - 行为：不再同步移动、不再落库位置；但仍保持 Presence 在线，仍在房间
    func finishMyGameAndWait() {
        // 0) 必须在房间里
        guard isInRoom else { return }
        guard meState?.status != .finished else { return } // ✅ 已经 finished 就不重复做

        // 1) 停止所有“行动同步”
        stopBroadcastMove()
        stopHeartbeat()

        // 2) 上报玩法状态（DB）
        updateMyStatus(.finished)

        // 3) 本地进入结算页
        withAnimation(.easeInOut) {
            phase = .gameOver
        }

        DLog.info("🏁 finishMyGameAndWait: stop move+heartbeat, status=finished, phase=gameOver")
    }



    // MARK: - ⑨ Broadcast Move 应用（体验层）

    /// ✅ 接收别人的高频坐标（Broadcast）
    func applyRemoteMove(userId: UUID, lat: Double, lng: Double, ts: Date, seq: Int) {
        // 忽略自己
        if userId == meId { return }

        // 防乱序
        let lastSeq = lastMoveSeqByUserId[userId] ?? -1
        if seq <= lastSeq { return }
        lastMoveSeqByUserId[userId] = seq

        guard let rid = self.roomId else {
            DLog.warn("applyRemoteMove ignored: roomId nil user=\(userId)")
            return
        }

        // ✅ 如果本地还没有这个人，就先建一个占位 state
        var s = statesByUserId[userId] ?? RoomPlayerState(
            roomId: rid,
            userId: userId,
            role: .runner,
            status: .active,
            lat: nil,
            lng: nil,
            updatedAt: ts,
            joinedAt: nil,
        )

        s.lat = lat
        s.lng = lng
        s.updatedAt = ts
        statesByUserId[userId] = s
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
                    self?.presenceOnlineIds = online
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
            
            // ✅ 关键：subscribeSync 能 return，说明 channel 至少已 subscribed 成功
            self.syncChannelConnected = true

            // ✅ 关键：避免 RoomService 的 presenceDidSyncOnce=true 但你没把回调传回 GameStore
            self.presenceDidSyncOnce = true
            
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
    
    @MainActor
    private func applyRoomEvent(_ ev: RoomEvent) {
        DLog.info("📨 room_event id=\(ev.id) type=\(ev.type) payload=\(String(describing: ev.payload))")

        guard ev.type == "item_used" else { return }

        guard let s = ev.payloadString("item_type"),
              let t = ItemType(rawValue: s),
              let def = ItemDef.byType[t]
        else {
            DLog.warn("⚠️ item_used but payload item_type decode failed")
            return
        }

        toastMessage = "🎯 有人使用：\(def.name)"
        itemNotification = def

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if itemNotification == def { itemNotification = nil }
            toastMessage = nil
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

    func applyUpsert(_ state: RoomPlayerState) {
        // 我自己：保护期内，保留本地 role
        if state.userId == meId {
            if Date().timeIntervalSince(lastLocalRoleChangeTime) < 2.0,
               let localState = statesByUserId[state.userId] {
                var merged = state
                merged.role = localState.role
                statesByUserId[state.userId] = merged
                return
            }
        }
        statesByUserId[state.userId] = state
    }

    // MARK: - Game Actions

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


