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

@MainActor
@Observable
final class GameStore {

    // MARK: - Dependencies
    private let locationService: LocationService
    private let routeService: RouteService
    private let roomService = RoomService()
    private let profileService = ProfileService()

    // MARK: - External
    var meId: UUID?

    // MARK: - Room State
    var roomId: UUID?
    var room: Room?
    var phase: GamePhase = .setup
    var selectedRegion: GameRegion = GameRegion.allCSURegions.first!
    var safeZone: SafeZone?

    /// ✅ 同步生命周期：只看是否仍在房间内（不要用 phase）
    private(set) var isInRoom: Bool = false

    /// 用于 grace：刚进房间的前 3 秒，不显示离线（等 presence sync）
    private var enteredRoomAt: Date? = nil

    // MARK: - 🛡️ Role Protection
    private var lastLocalRoleChangeTime: Date = .distantPast
    private var roleUpdateTask: Task<Void, Never>?

    // MARK: - Realtime Cache (DB 真相 + 广播补充)
    var statesByUserId: [UUID: RoomPlayerState] = [:]

    // MARK: - Presence (真在线)
    var presenceOnlineIds: Set<UUID> = []

    // MARK: - Broadcast 防乱序
    private var lastMoveSeqByUserId: [UUID: Int] = [:]
    private var myMoveSeq: Int = 0

    // MARK: - UI State
    var currentRoute: MKRoute?
    var trackingTargetId: UUID?
    var errorMessage: String?

    // MARK: - Timer
    private var gameTimer: Timer?

    // MARK: - DB Heartbeat（低频落库）
    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval = 2.0

    // MARK: - Broadcast Move（高频移动同步）
    private var broadcastMoveTask: Task<Void, Never>?
    private let broadcastInterval: TimeInterval = 0.10 // 10Hz（推荐 0.08~0.15）

    // MARK: - Profile Cache
    var profileCache: [UUID: ProfileService.ProfileInfo] = [:]
    private var fetchingIds: Set<UUID> = []

    // MARK: - Computed / Derived
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

    var onlinePlayers: [PlayerDisplay] {
        mapPlayers.filter { !$0.isOffline }
    }

    var lobbyPlayers: [LobbyPlayerDisplay] {
        let now = Date()
        let allUserIds = statesByUserId.keys

        let missingIds = allUserIds.filter {
            profileCache[$0] == nil && !fetchingIds.contains($0)
        }
        if !missingIds.isEmpty {
            Task { await fetchMissingProfiles(ids: Array(missingIds)) }
        }

        return statesByUserId.values.map { state in
            let info = profileCache[state.userId]
            let isOnline = presenceOnlineIds.contains(state.userId)
            let isStale  = state.isStale(now: now, threshold: 8.0)

            return LobbyPlayerDisplay(
                id: state.userId,
                displayName: info?.name ?? "Player \(state.userId.uuidString.prefix(4))",
                role: state.role,
                status: state.status,
                isMe: state.userId == meId,
                isOnline: isOnline,
                isStale: isStale
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Init
    init(
        locationService: LocationService = LocationService(),
        routeService: RouteService = RouteService()
    ) {
        self.locationService = locationService
        self.routeService = routeService
    }

    // MARK: - ===== UI 派生数据（❗不写入数据库） =====

    var mapPlayers: [PlayerDisplay] {
        let now = Date()

        let allUserIds = statesByUserId.keys
        let missingIds = allUserIds.filter { id in
            profileCache[id] == nil && !fetchingIds.contains(id)
        }
        if !missingIds.isEmpty {
            Task { await fetchMissingProfiles(ids: Array(missingIds)) }
        }

        return statesByUserId.values.compactMap { state in
            guard let coordinate = state.coordinate else { return nil }

            let dbStatus = state.status
            let isOnlineByPresence = presenceOnlineIds.contains(state.userId)

            // ✅ grace：刚进房间 3 秒内，不显示离线（等 presence sync）
            let inGrace = (enteredRoomAt.map { now.timeIntervalSince($0) < 3.0 } ?? false)

            // ✅ 离线只由 presence 决定（grace 期间强制在线）
            let isOffline = inGrace ? false : !isOnlineByPresence

            // ✅ stale 你可以留着做“定位停更/信号弱”，不要混进 offline
            _ = state.isStale(now: now, threshold: 8.0)

            let cachedInfo = profileCache[state.userId]
            let displayName = cachedInfo?.name ?? "Player \(state.userId.uuidString.prefix(4))"

            var exposed = false
            if let zone = self.safeZone {
                let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let centerLoc = CLLocation(latitude: zone.center.latitude, longitude: zone.center.longitude)
                if userLoc.distance(from: centerLoc) > zone.radius {
                    exposed = true
                }
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
        .sorted { $0.displayName < $1.displayName }
    }

    var me: PlayerDisplay? {
        guard let meId else { return nil }
        return mapPlayers.first(where: { $0.id == meId })
    }

    var trackingTarget: PlayerDisplay? {
        guard let trackingTargetId else { return nil }
        return mapPlayers.first(where: { $0.id == trackingTargetId })
    }

    // MARK: - ===== UI 可绑定入口（Picker） =====

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

    var meRole: GameRole {
        get { meState?.role ?? .runner }
        set {
            var s = meState ?? makePlaceholderMeState(defaultRole: newValue)
            s.role = newValue
            meState = s
        }
    }

    // MARK: - ===== Setup 生命周期 =====

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

    // MARK: - ===== Game Flow（本地模拟） =====

    func startGameLocal() {
        safeZone = SafeZone(center: selectedRegion.center, radius: selectedRegion.initialRadius)
        withAnimation(.easeInOut) { phase = .playing }
        locationService.start()
        startZoneShrinking()
    }

    func endGameLocal() {
        stopZoneShrinking()
        currentRoute = nil
        trackingTargetId = nil
        withAnimation(.easeInOut) { phase = .gameOver }
    }

    func backToSetup() {
        stopZoneShrinking()
        currentRoute = nil
        trackingTargetId = nil
        safeZone = nil
        withAnimation(.easeInOut) { phase = .setup }
        locationService.start()
    }

    // MARK: - ===== 安全区缩圈 =====

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

    // MARK: - ===== Navigation =====

    func navigate(to userId: UUID) async {
        trackingTargetId = userId
        guard let target = mapPlayers.first(where: { $0.id == userId }) else { return }

        do {
            let route = try await routeService.walkingRoute(to: target.coordinate)
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

    // MARK: - ===== Realtime 入口（Supabase） =====

    func applyRemove(userId: UUID) {
        statesByUserId.removeValue(forKey: userId)
        lastMoveSeqByUserId.removeValue(forKey: userId)
    }

    /// ✅ rooms 更新入口（由 RoomService rooms realtime 回调触发）
    func applyRoomUpdate(_ room: Room) {
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
                if meState?.status != .ready {
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

    /// ✅ 投降：是玩法状态，不等于离线
    func playerSurrender() {
        stopHeartbeat()
        stopBroadcastMove()

        // 玩法上投降：建议 caught（或你未来加 spectator）
        updateMyStatus(.caught)

        withAnimation(.easeInOut) { phase = .gameOver }
        DLog.info("🏳️ 玩家投降：已停止同步并上报 caught")
    }

    // MARK: - ===== Broadcast Move 应用（体验层） =====

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
            joinedAt: nil,
            updatedAt: ts
        )

        s.lat = lat
        s.lng = lng
        s.updatedAt = ts
        statesByUserId[userId] = s
    }

    // MARK: - ===== Reset =====

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

    // MARK: - Helpers

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
            joinedAt: nil,
            updatedAt: Date()
        )
    }

    // MARK: - ===== DB 低频落库（给裁判用） =====

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

    // MARK: - ===== Broadcast 高频移动同步 =====

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

    // MARK: - ===== Room Flow =====

    func joinRoom(roomId: UUID) async {
        guard let meId else {
            errorMessage = "未登录"
            return
        }

        locationService.requestPermission()
        locationService.start()

        self.roomId = roomId
        errorMessage = nil

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

        do {
            // ✅ rooms realtime：先订阅
            try await roomService.subscribeRoom(roomId: roomId)

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

    func leaveRoom() async {
        // ✅ 第一时间告诉所有同步任务：房间已结束
        self.isInRoom = false

        // ✅ 停止同步
        stopHeartbeat()
        stopBroadcastMove()

        // ✅ 不再写 status=offline 表示离线（在线由 Presence 决定）
        // 如果你希望离开就消失：调用 removeMeFromRoom
        if let roomId, let meId {
            // 可选：离房删除行
            // try? await roomService.removeMeFromRoom(roomId: roomId, meId: meId)
            _ = roomId
            _ = meId
        }

        await roomService.unsubscribeSync()
        await roomService.unsubscribeRoom()
        await roomService.leaveRoom()

        resetRoomState()
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

        do {
            try await roomService.updateRoomStatus(roomId: roomId, status: "playing")
            withAnimation(.easeInOut) { self.phase = .playing }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeRoom() async {
        guard isHost else { errorMessage = "只有房主可以关闭房间"; return }
        guard let roomId else { return }
        do {
            try await roomService.updateRoomStatus(roomId: roomId, status: "closed")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exitGame() async {
        if isHost { await closeRoom() }
        await leaveRoom()
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

    // MARK: - Profile load

    private func fetchMissingProfiles(ids: [UUID]) async {
        for id in ids { fetchingIds.insert(id) }

        let newProfiles = await profileService.fetchProfilesAndSignAvatars(ids: ids)
        for (uid, info) in newProfiles { self.profileCache[uid] = info }

        for id in ids { fetchingIds.remove(id) }
    }

    // MARK: - Utils

    func distanceTo(_ targetCoordinate: CLLocationCoordinate2D) -> Double {
        guard let myLoc = locationService.currentLocation else { return 999_999 }
        let p1 = CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude)
        let p2 = CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
        return p1.distance(from: p2)
    }
}

struct LobbyPlayerDisplay: Identifiable {
    let id: UUID
    let displayName: String
    let role: GameRole
    let status: PlayerStatus
    let isMe: Bool
    let isOnline: Bool
    let isStale: Bool
}
