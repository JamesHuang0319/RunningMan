//
//  GameStore.swift
//  RunningMan
//
//  游戏状态唯一协调者（Room / Players / Zone / Navigation）
//  ⚠️ 不存数据库真相，只缓存 Realtime 下发的状态
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
    // ✅ 新增：ProfileService 实例 (用于拉取资料)
    private let profileService = ProfileService()

    // MARK: - External (由 App / AuthStore 注入)
    /// 当前登录用户（auth.users.id）
    var meId: UUID?
    // MARK: - 🛡️ 状态保护机制
    /// 记录最后一次本地修改角色的时间
    private var lastLocalRoleChangeTime: Date = .distantPast

    // MARK: - Room State
    var roomId: UUID?
    var phase: GamePhase = .setup
    var selectedRegion: GameRegion = GameRegion.allCSURegions.first!
    var safeZone: SafeZone?

    // MARK: - Realtime Cache (唯一真相的本地缓存)
    /// room_players 表的实时状态缓存：key = userId
    var statesByUserId: [UUID: RoomPlayerState] = [:]

    // MARK: - UI State
    var currentRoute: MKRoute?
    var trackingTargetId: UUID?
    var errorMessage: String?

    // MARK: - Timer
    private var gameTimer: Timer?

    // MARK: - Heartbeat
    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval = 2.0

    // ✅ MOD: rooms 真相（rooms 表）
    var room: Room?
    var isHost: Bool { room?.createdBy == meId }

    // ✅ 新增：资料缓存 [UserID : 资料]
    var profileCache: [UUID: ProfileService.ProfileInfo] = [:]

    // ✅ 新增：防止重复请求的集合
    private var fetchingIds: Set<UUID> = []

    // ✅ MOD: Lobby 用：在线玩家（先用 isOffline，最稳）
    var onlinePlayers: [PlayerDisplay] {
        players.filter { !$0.isOffline }
    }

    // MARK: - Init
    init(
        locationService: LocationService = LocationService(),
        routeService: RouteService = RouteService()
    ) {
        self.locationService = locationService
        self.routeService = routeService
    }
    private var roleUpdateTask: Task<Void, Never>?

    // MARK: - ===== UI 派生数据（❗不写入数据库） =====

    var players: [PlayerDisplay] {
        let now = Date()

        // 1. 找出所有当前存在的玩家 ID
        let allUserIds = statesByUserId.keys

        // 2. 找出哪些 ID 还没有缓存数据，且没有正在加载
        let missingIds = allUserIds.filter { id in
            profileCache[id] == nil && !fetchingIds.contains(id)
        }

        // 3. 触发异步加载 (副作用)
        if !missingIds.isEmpty {
            Task { await fetchMissingProfiles(ids: Array(missingIds)) }
        }

        return statesByUserId.values.compactMap { state in
            guard let coordinate = state.coordinate else { return nil }

            let dbStatus = state.status
            let isDbOffline = dbStatus == .offline
            let isTimeout = state.isStale(now: now, threshold: 8.0)

            // --- 🟢 从缓存组装数据 ---
            let cachedInfo = profileCache[state.userId]
            let displayName =
                cachedInfo?.name
                ?? "Player \(state.userId.uuidString.prefix(4))"

            // ✅ 新增：计算是否暴露 (在安全区外)
            var exposed = false
            if let zone = self.safeZone {
                let userLoc = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                let centerLoc = CLLocation(
                    latitude: zone.center.latitude,
                    longitude: zone.center.longitude
                )
                // 如果距离 > 半径，即为暴露
                if userLoc.distance(from: centerLoc) > zone.radius {
                    exposed = true
                }
            }

            return PlayerDisplay(
                id: state.userId,
                roomId: state.roomId,
                displayName: displayName,  // ✅ 真实昵称
                avatarDownloadURL: cachedInfo?.avatarDownloadURL,  // ✅ 临时 URL
                avatarCacheKey: cachedInfo?.avatarPath,  // ✅ 永久 Path (作为 Key)
                role: state.role,
                status: dbStatus,
                coordinate: coordinate,
                lastSeenAt: state.updatedAt,
                isMe: state.userId == meId,
                isOffline: isDbOffline || isTimeout,
                isExposed: exposed // ✅ 传入
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    var me: PlayerDisplay? {
        guard let meId else { return nil }
        return players.first(where: { $0.id == meId })
    }

    var trackingTarget: PlayerDisplay? {
        guard let trackingTargetId else { return nil }
        return players.first(where: { $0.id == trackingTargetId })
    }

    // MARK: - ===== UI 可绑定入口（给 SwiftUI Picker 用） =====

    /// 当前用户在 statesByUserId 里的 state（可读写的中间层）
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

    /// 供 SetupSheet Picker 绑定使用
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

        let userLoc = CLLocation(
            latitude: user.latitude,
            longitude: user.longitude
        )

        if let nearest = GameRegion.allCSURegions.min(by: { a, b in
            userLoc.distance(
                from: CLLocation(
                    latitude: a.center.latitude,
                    longitude: a.center.longitude
                )
            )
                < userLoc.distance(
                    from: CLLocation(
                        latitude: b.center.latitude,
                        longitude: b.center.longitude
                    )
                )
        }) {
            selectedRegion = nearest
        }
    }

    // MARK: - ===== Game Flow（本地模拟，未来可由服务器驱动） =====

    func startGameLocal() {
        safeZone = SafeZone(
            center: selectedRegion.center,
            radius: selectedRegion.initialRadius
        )

        withAnimation(.easeInOut) {
            phase = .playing
        }

        locationService.start()
        startZoneShrinking()
    }

    func endGameLocal() {
        stopZoneShrinking()
        currentRoute = nil
        trackingTargetId = nil

        withAnimation(.easeInOut) {
            phase = .gameOver
        }
    }

    func backToSetup() {
        stopZoneShrinking()
        currentRoute = nil
        trackingTargetId = nil
        safeZone = nil

        withAnimation(.easeInOut) {
            phase = .setup
        }

        locationService.start()
    }

    // MARK: - ===== 安全区缩圈 =====

    private func startZoneShrinking() {
        stopZoneShrinking()

        let tick: TimeInterval = 0.5
        let shrinkPerTick: CLLocationDistance = 5

        gameTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true)
        { [weak self] _ in
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
        guard let target = players.first(where: { $0.id == userId }) else {
            return
        }

        do {
            let route = try await routeService.walkingRoute(
                to: target.coordinate
            )
            withAnimation(.easeInOut) {
                currentRoute = route
            }
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

    //    func applyUpsert(_ state: RoomPlayerState) {
    //        statesByUserId[state.userId] = state
    //    }

    func applyRemove(userId: UUID) {
        statesByUserId.removeValue(forKey: userId)
    }

    // ✅ MOD: rooms 更新入口（由 RoomService rooms realtime 回调触发）
    func applyRoomUpdate(_ room: Room) {
        self.room = room

        // 1. 同步区域 (Region Sync)
        if let rid = room.regionId {
            // 只有当 ID 真的变了，才去查找和更新，避免无意义刷新
            if selectedRegion.id != rid {
                if let matched = GameRegion.allCSURegions.first(where: {
                    $0.id == rid
                }) {
                    print("🗺️ [GameStore] 收到远程区域更新: \(matched.name)")
                    // ⚠️ 关键：使用 withAnimation 包裹赋值，强制通知 UI 做动画
                    withAnimation(.easeInOut(duration: 1.0)) {
                        self.selectedRegion = matched
                    }
                } else {
                    print("⚠️ [GameStore] 收到未知区域ID: \(rid)")
                }
            }
        }

        switch room.status {
        case .waiting:
            // 如果是从结束/进行中回来，必须停止缩圈
            stopZoneShrinking()
            cancelNavigation()  // 清理导航线
            if phase != .lobby {
                withAnimation(.easeInOut) { phase = .lobby }
                // 回到大厅时，重置为已准备 (防止上一局被抓的状态带回来)
                if meState?.status != .ready {
                    updateMyStatus(.ready)
                }
            }

        case .playing:
            if safeZone == nil {
                safeZone = SafeZone(
                    center: selectedRegion.center,
                    radius: selectedRegion.initialRadius
                )
            }
            locationService.start()
            startZoneShrinking()

            if phase != .playing {
                withAnimation(.easeInOut) { phase = .playing }
                // ✅ 核心修复：游戏开始瞬间，如果你是 ready，自动变为 active (复活/开始)
                // 注意：如果已经是 .caught (断线重连)，则不要变回 active
                if let myState = statesByUserId[meId ?? UUID()],
                    myState.status == .ready
                {
                    print("🚀 游戏开始，状态切换 ready -> active")
                    updateMyStatus(.active)
                }

            }

        case .ended:
            stopZoneShrinking()
            cancelNavigation()  // 比赛结束不应再有路线指示
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

    // ✅ 新增辅助方法：更新自己的 Status
    // GameStore.swift

    func updateMyStatus(_ newStatus: PlayerStatus) {
        guard let roomId, let meId else { return }

        // 1. 乐观更新本地缓存
        if var s = statesByUserId[meId] {
            // ✅ 修复点：这里直接赋枚举值，不要加 .rawValue
            s.status = newStatus
            statesByUserId[meId] = s
        }

        // 2. 推送给服务器
        Task {
            try? await roomService.upsertMyState(
                roomId: roomId,
                meId: meId,
                role: meRole.rawValue,
                status: newStatus.rawValue,  // ✅ 这里要转为 String 发给数据库
                lat: locationService.currentLocation?.latitude,
                lng: locationService.currentLocation?.longitude
            )
        }
    }

    // MARK: - GameStore.swift 添加

    /// 普通玩家主动投降/结束奔跑
    func playerSurrender() {
        // 1. 🛑 立即停止心跳
        // 必须先停，否则下一秒心跳任务可能会覆盖我们即将发送的状态
        stopHeartbeat()

        // 2. 📡 告诉服务器：我下线了/退出了
        // 使用 offline，这样你在别人的地图上会立即变灰或消失
        // (updateMyStatus 内部已经包含了更新本地缓存和发送 RPC/DB请求的逻辑)
        updateMyStatus(.offline)

        // 3. 📺 本地切换 UI 到结算页
        withAnimation(.easeInOut) {
            self.phase = .gameOver
        }

        DLog.info("🏳️ 玩家主动投降，已停止心跳并发送 offline")
    }
    // MARK: - ===== Reset =====
    func resetRoomState() {
        roomId = nil
        room = nil  // ✅ MOD
        phase = .setup
        safeZone = nil
        stopZoneShrinking()

        statesByUserId.removeAll()

        currentRoute = nil
        trackingTargetId = nil
        errorMessage = nil
    }

    // MARK: - Helpers

    private func makePlaceholderMeState(defaultRole: GameRole)
        -> RoomPlayerState
    {
        let id = meId ?? UUID()
        let room = roomId ?? UUID()

        return RoomPlayerState(
            roomId: room,
            userId: id,
            role: defaultRole,
            status: .active,
            lat: nil,
            lng: nil,
            updatedAt: Date()
        )
    }

    private func startHeartbeat() {
        stopHeartbeat()

        heartbeatTask = Task { [weak self] in
            guard let self else { return }

            DLog.ok("heartbeat started interval=\(self.heartbeatInterval)s")

            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000)
                )

                guard let roomId = self.roomId, let meId = self.meId else {
                    continue
                }

                guard let loc = self.locationService.currentLocation else {
                    DLog.warn("heartbeat: no location yet")
                    continue
                }

                // ✅ 必须使用正确的 Role (runner/hunter)
                let myCurrentRole = self.meRole.rawValue
                // ✅ 必须使用正确的 Status (active/ready)
                let myCurrentStatus =
                    self.statesByUserId[meId]?.status.rawValue
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
                    DLog.warn(
                        "heartbeat upsert failed: \(error.localizedDescription)"
                    )
                }
            }

            DLog.warn("heartbeat ended")
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
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

        roomService.setRoomPlayersCallbacks(
            onUpsert: { [weak self] state in
                Task { @MainActor in self?.applyUpsert(state) }
            },
            onDelete: { [weak self] userId in
                Task { @MainActor in self?.applyRemove(userId: userId) }
            }
        )

        roomService.setRoomCallback(onUpdate: { [weak self] room in
            Task { @MainActor in self?.applyRoomUpdate(room) }
        })

        do {
            // ✅ 1) rooms realtime：先订阅，避免漏掉 snapshot 前后的更新
            try await roomService.subscribeRoom(roomId: roomId)

            // ✅ 2) rooms snapshot：订阅后再拉一把真相
            let r = try await roomService.fetchRoom(roomId: roomId)
            applyRoomUpdate(r)

            // ✅ 3) players snapshot + realtime（你 RoomService 内部建议也改成“先订阅再 snapshot”，但这里先不动也能跑）
            let snapshot = try await roomService.joinRoom(
                roomId: roomId,
                meId: meId,
                initialRole: meRole.rawValue,
                initialStatus: PlayerStatus.ready.rawValue
            )
            snapshot.forEach { applyUpsert($0) }

            startHeartbeat()

            // ✅ 4) ❌ 删掉强制 lobby，phase 由 applyRoomUpdate / rooms realtime 驱动
            // if self.phase == .setup { withAnimation(.easeInOut) { self.phase = .lobby } } // <- 如果你要兜底才留

            DLog.ok("joinRoom OK snapshot=\(snapshot.count)")
        } catch {
            errorMessage = error.localizedDescription
            DLog.err("joinRoom failed: \(error.localizedDescription)")
        }
    }

    // ✅ MOD: leaveRoom -> 同时退出 rooms realtime
    func leaveRoom() async {
        stopHeartbeat()  // 1. 先停心跳，防止刚改成 offline 又被心跳改成 active

        if let roomId, let meId {
            // 2. 主动告知数据库：我下线了
            // 这里传 .offline.rawValue 字符串
            try? await roomService.upsertMyState(
                roomId: roomId,
                meId: meId,
                role: meRole.rawValue,
                status: PlayerStatus.offline.rawValue,
                lat: nil,
                lng: nil
            )

            // 3. 彻底删除记录（可选）
            // 如果你希望玩家退出后直接消失，就保留 removeMeFromRoom
            // 如果希望玩家变灰显示“离线”，就注释掉下面这行，只保留上面的 upsert
            //            try? await roomService.removeMeFromRoom(roomId: roomId, meId: meId)
        }

        // ✅ MOD: rooms unsubscribe（需要你在 RoomService 里实现）
        await roomService.unsubscribeRoom()

        await roomService.leaveRoom()
        resetRoomState()
        DLog.ok("leaveRoom done")
    }

    // ✅ MOD: createRoomAndJoin -> 创建房间后 join，然后进入 lobby 等待
    func createRoomAndJoin() async {
        await createRoomAndJoin(regionId: self.selectedRegion.id)
    }

    // ✅ MOD: 创建房间时把 regionId 写入 rooms（你 RoomService.createRoom 已支持 regionId）
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

    // ✅ MOD: 房主锁定区域（写 rooms.region_id）
    func lockSelectedRegion() async {
        guard isHost else {
            errorMessage = "只有房主可以锁定区域"
            return
        }
        guard let roomId else { return }

        do {
            try await roomService.lockRoomRegion(
                roomId: roomId,
                regionId: selectedRegion.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ✅ 唯一入口（Lobby 用这个）
    func startRoomGame() async {
        DLog.info(
            "[GameStore] startRoomGame called. meId=\(meId?.uuidString ?? "nil") roomId=\(roomId?.uuidString ?? "nil") isHost=\(isHost) canStartGame=\(canStartGame)"
        )

        guard isHost else {
            DLog.warn("[GameStore] startRoomGame blocked: not host")
            errorMessage = "只有房主可以开始"
            return
        }

        guard let roomId else {
            DLog.warn("[GameStore] startRoomGame blocked: roomId nil")
            errorMessage = "roomId 为空"
            return
        }

        guard canStartGame else {
            DLog.warn("[GameStore] startRoomGame blocked: canStartGame false")
            errorMessage = "未进入房间"
            return
        }

        do {
            DLog.info("[GameStore] updating room status -> playing")
            try await roomService.updateRoomStatus(
                roomId: roomId,
                status: "playing"
            )

            withAnimation(.easeInOut) {
                self.phase = .playing
            }

            DLog.ok("[GameStore] updateRoomStatus done")
        } catch {
            DLog.err(
                "[GameStore] updateRoomStatus failed: \(error.localizedDescription)"
            )
            errorMessage = error.localizedDescription
        }
    }

    // ✅ MOD: 房主关闭房间（写 rooms.status=closed）
    func closeRoom() async {
        guard isHost else {
            errorMessage = "只有房主可以关闭房间"
            return
        }
        guard let roomId else { return }

        do {
            try await roomService.updateRoomStatus(
                roomId: roomId,
                status: "closed"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ✅ MOD: 单人测试用——只要进了房间就能开始
    var canStartGame: Bool {
        roomId != nil
    }

    // ✅ MOD: 把我的 role 推到服务器（切换 Picker 时调用）
    func pushMyRoleToServer() async {
        guard let roomId, let meId else { return }
        do {
            try await roomService.upsertMyState(
                roomId: roomId,
                meId: meId,
                role: meRole.rawValue,
                status: "active",
                lat: nil,
                lng: nil
            )
        } catch {
            DLog.warn(
                "pushMyRoleToServer failed: \(error.localizedDescription)"
            )
        }
    }

    // ✅ MOD: Host 锁定区域（写 rooms.region_id）
    func lockRoomRegion(roomId: UUID, regionId: UUID) async {
        do {
            try await roomService.lockRoomRegion(
                roomId: roomId,
                regionId: regionId
            )
        } catch {
            errorMessage = error.localizedDescription
            DLog.err("lockRoomRegion failed: \(error.localizedDescription)")
        }
    }

    // 1️⃣ 修改 updateRole：记录修改时间，且立即更新本地缓存
    func updateRole(to newRole: GameRole) {
        // A. 记录当前时间，开启“保护盾”
        lastLocalRoleChangeTime = Date()

        // B. 乐观更新：立即修改本地缓存 (UI 会立刻变，且不会被心跳覆盖)
        if var myState = statesByUserId[meId ?? UUID()] {
            myState.role = newRole
            statesByUserId[meId ?? UUID()] = myState
        } else {
            // 如果还没状态，造一个
            meRole = newRole
        }

        // C. 防抖逻辑 (保持不变)
        roleUpdateTask?.cancel()
        roleUpdateTask = Task {
            do {
                try await Task.sleep(for: .seconds(0.6))
                if Task.isCancelled { return }
                await pushMyRoleToServer()  // 发送请求
            } catch {}
        }
    }

    // 2️⃣ 修改 applyUpsert：如果处于保护期，忽略服务器对“我”的更新
    func applyUpsert(_ state: RoomPlayerState) {
        // 如果这条更新是关于“我”的
        if state.userId == meId {
            // 检查：如果我最近 2秒内 刚手动改过角色
            if Date().timeIntervalSince(lastLocalRoleChangeTime) < 2.0 {
                // 🛡️ 触发保护：只接受位置更新，忽略服务器发来的旧角色/旧状态
                // 这样你的 UI 就不会跳回去了
                if var localState = statesByUserId[state.userId] {
                    // 保留我本地选的角色
                    var mergedState = state
                    mergedState.role = localState.role
                    statesByUserId[state.userId] = mergedState
                    return
                }
            }
        }

        // 其他情况（别人，或者保护期已过），无脑信任服务器
        statesByUserId[state.userId] = state
    }

    // MARK: - ===== 路由流转 (多人联机优化版) =====

    /// [新增] 房主发起：结束当前对局，进入结算
    func hostEndGame() async {
        guard isHost, let roomId else { return }
        do {
            // 更新数据库，applyRoomUpdate 会感知到并让所有人切换到 .gameOver
            try await roomService.updateRoomStatus(
                roomId: roomId,
                status: RoomStatus.ended.rawValue,
                winner: nil
            )
            DLog.ok("房主终止了游戏，正在进入结算页...")
        } catch {
            errorMessage = "结束游戏失败: \(error.localizedDescription)"
        }
    }

    /// [新增] 房主发起：再来一局（从结算页回到大厅）
    func hostRematch() async {
        guard isHost, let roomId else { return }
        do {
            // 将状态改回 waiting，所有人会自动切回 .lobby 准备
            try await roomService.updateRoomStatus(
                roomId: roomId,
                status: RoomStatus.waiting.rawValue
            )
            DLog.ok("房主发起了再来一局")
        } catch {
            errorMessage = "发起重开失败: \(error.localizedDescription)"
        }
    }

    /// [优化] 彻底离开：清理并返回首页

    // MARK: - ===== 路由流转 (多人联机优化版) =====

    /// [优化] 彻底离开：清理并返回首页
    func exitGame() async {
        // ✅ 逻辑补全：如果是房主退出，为了让其他特工也同步退回首页，先执行关闭房间
        if isHost {
            await closeRoom()  // 这会将数据库 status 设为 'closed'
        }

        await leaveRoom()  // 内部包含停止心跳、删除 room_players 记录、resetRoomState 等
    }

    // MARK: - ===== UI 派生数据 (View Support) =====

    /// 根据当前游戏阶段和身份，给用户的操作指令提示
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

    func attemptTag(targetUserId: UUID) async throws -> AttemptTagResult {
        guard let roomId else {
            throw NSError(
                domain: "GameStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "roomId nil"]
            )
        }
        return try await roomService.attemptTag(
            roomId: roomId,
            targetUserId: targetUserId
        )
    }

    private func fetchMissingProfiles(ids: [UUID]) async {
        // 标记为正在加载
        for id in ids { fetchingIds.insert(id) }

        // 调用 Service
        let newProfiles = await profileService.fetchProfilesAndSignAvatars(
            ids: ids
        )

        // 更新缓存 (触发 UI 刷新)
        for (uid, info) in newProfiles {
            self.profileCache[uid] = info
        }

        // 移除标记 (如果失败了，下次还会重试，这里简化处理)
        for id in ids { fetchingIds.remove(id) }
    }
    
    /// 计算当前用户到目标坐标的距离（米）
    /// 如果获取不到当前位置，返回无穷大或 0
    func distanceTo(_ targetCoordinate: CLLocationCoordinate2D) -> Double {
        guard let myLoc = locationService.currentLocation else {
            return 999999 // 返回一个极大值，避免逻辑误判
        }
        
        let p1 = CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude)
        let p2 = CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
        
        return p1.distance(from: p2)
    }

}

extension Date {
    fileprivate func isStaleComparedTo(now: Date, threshold: TimeInterval = 8.0)
        -> Bool
    {
        now.timeIntervalSince(self) > threshold
    }
}
