//
//  RoomService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//

import Foundation
import Supabase

@MainActor
final class RoomService {

    // MARK: - Config

    struct Config {
        var upsertMeOnJoin: Bool = true
    }

    enum RoomServiceError: LocalizedError {
        case missingUserId
        case decodeFailed(String)

        case missingRoomId
        case roomDecodeFailed(String)

        case syncNotReady

        var errorDescription: String? {
            switch self {
            case .missingUserId:
                return "缺少当前用户 id"
            case .decodeFailed(let msg):
                return "数据解析失败：\(msg)"

            case .missingRoomId:
                return "缺少 room id"
            case .roomDecodeFailed(let msg):
                return "房间数据解析失败：\(msg)"

            case .syncNotReady:
                return "同步通道尚未准备好"
            }
        }
    }

    // MARK: - Dependencies

    private let client: SupabaseClient
    private let config: Config

    init(
        client: SupabaseClient = SupabaseClientProvider.shared.client,
        config: Config = .init()
    ) {
        self.client = client
        self.config = config
    }

    // MARK: - Realtime: room_players (Postgres changes)

    private var channel: RealtimeChannelV2?
    private var changesTask: Task<Void, Never>?
    private(set) var subscribedRoomId: UUID?

    // Callbacks (room_players)
    private var onUpsert: ((RoomPlayerState) -> Void)?
    private var onDelete: ((UUID) -> Void)?

    func setRoomPlayersCallbacks(
        onUpsert: @escaping (RoomPlayerState) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.onUpsert = onUpsert
        self.onDelete = onDelete
    }

    // MARK: - Realtime: rooms (Postgres changes)

    private var roomChannel: RealtimeChannelV2?
    private var roomChangesTask: Task<Void, Never>?
    private(set) var subscribedRoomsId: UUID?
    private var onRoomUpdate: ((Room) -> Void)?

    func setRoomCallback(onUpdate: @escaping (Room) -> Void) {
        self.onRoomUpdate = onUpdate
    }

    // MARK: - ✅ Sync Layer (Broadcast + Presence)

    private var syncChannel: RealtimeChannelV2?
    private var moveSub: RealtimeSubscription?
    private var presenceSub: RealtimeSubscription?
    private var syncStatusSub: RealtimeSubscription?

    private var trackedMeId: UUID?

    private var onMove: (@MainActor (UUID, Double, Double, Date, Int) -> Void)?
    private var onPresenceSync: (@MainActor (Set<UUID>) -> Void)?

    private var onlineIds: Set<UUID> = []

    /// ✅ 标记：WebSocket subscribe 是否真正完成（用于 broadcastMove gating）
    private var syncSubscribed: Bool = false

    /// ✅ 防止重复 track；在断网/重连后会复位，允许重新 track
    private var didTrackOnce: Bool = false

    func setSyncCallbacks(
        onMove: @escaping @MainActor (UUID, Double, Double, Date, Int) -> Void,
        onPresenceSync: @escaping @MainActor (Set<UUID>) -> Void
    ) {
        self.onMove = onMove
        self.onPresenceSync = onPresenceSync
    }

    // MARK: - Broadcast payload (move)

    struct MovePayload: Codable, Sendable {
        let user_id: String
        let lat: Double
        let lng: Double
        let ts: String
        let seq: Int
    }

    /// ✅ Realtime broadcast 常见结构：{ "event": "...", "payload": { ... } }
    private struct BroadcastEnvelope<T: Decodable>: Decodable {
        let event: String?
        let payload: T?
    }

    /// ✅ 统一处理：从 broadcast message 中安全地解析 MovePayload
    /// - 先尝试 envelope（payload 包裹）
    /// - 再兜底尝试直接解 payload（某些版本可能直接给 payload）
    nonisolated
    private func decodeMovePayload(from message: JSONObject) throws -> MovePayload {
        // ① envelope: { event, payload: {...} }
        do {
            let env = try message.decode(as: BroadcastEnvelope<MovePayload>.self)
            if let payload = env.payload { return payload }
        } catch {
            // ignore, fallback
        }

        // ② payload 在 message["payload"]
        if let payloadObj = message["payload"]?.objectValue {
            return try payloadObj.decode(as: MovePayload.self)
        }

        // ③ 兜底：直接把 message 当 payload
        return try message.decode(as: MovePayload.self)
    }

    /// ✅ 统一派发 onMove（避免在多个地方重复写 UUID/Date/Task）
    nonisolated
    private func emitMove(_ payload: MovePayload) {
        guard let uid = UUID(uuidString: payload.user_id) else { return }
        let dt = ISO8601DateFormatter().date(from: payload.ts) ?? Date()

        Task { @MainActor in
            self.onMove?(uid, payload.lat, payload.lng, dt, payload.seq)
        }
    }

    // MARK: - Join / Leave

    func joinRoom(
        roomId: UUID,
        meId: UUID?,
        initialRole: String = "runner",
        initialStatus: String = PlayerStatus.ready.rawValue
    ) async throws -> [RoomPlayerState] {
        guard let meId else {
            DLog.err("[RoomService] joinRoom failed: missing user ID")
            throw RoomServiceError.missingUserId
        }

        DLog.info("[RoomService] joinRoom started roomId=\(roomId.uuidString) meId=\(meId.uuidString)")

        // 1) 先订阅 room_players realtime
        try await subscribeRoomPlayers(roomId: roomId)

        // 2) 再拉 snapshot
        var snapshot = try await fetchRoomPlayers(roomId: roomId)

        // 3) upsert 自己（可选）
        if config.upsertMeOnJoin {
            try await upsertMyState(
                roomId: roomId,
                meId: meId,
                role: initialRole,
                status: initialStatus,
                lat: nil,
                lng: nil
            )

            // 再拉一次 snapshot（最稳）
            snapshot = try await fetchRoomPlayers(roomId: roomId)
        }

        DLog.ok("[RoomService] joinRoom completed snapshot=\(snapshot.count)")
        return snapshot
    }

    func leaveRoom() async {
        DLog.warn("[RoomService] leaveRoom roomId=\(subscribedRoomId?.uuidString ?? "-")")

        // ✅ 退出时释放 Sync 层
        await unsubscribeSync()

        // ✅ 退出 room_players / rooms
        await unsubscribe()
        await unsubscribeRoom()

        subscribedRoomId = nil
    }

    // MARK: - Snapshot: room_players / rooms

    func fetchRoomPlayers(roomId: UUID) async throws -> [RoomPlayerState] {
        do {
            let res = try await client
                .from("room_players")
                .select()
                .eq("room_id", value: roomId.uuidString.lowercased())
                .execute()

            do {
                return try isoDecoder.decode([RoomPlayerState].self, from: res.data)
            } catch {
                throw RoomServiceError.decodeFailed(error.localizedDescription)
            }
        } catch {
            DLog.err("[RoomService] fetchRoomPlayers failed: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchRoom(roomId: UUID) async throws -> Room {
        let res = try await client
            .from("rooms")
            .select()
            .eq("id", value: roomId.uuidString.lowercased())
            .single()
            .execute()

        do {
            return try isoDecoder.decode(Room.self, from: res.data)
        } catch {
            if let jsonString = String(data: res.data, encoding: .utf8) {
                DLog.err("[RoomService] fetchRoom decode failed raw=\(jsonString)")
            }
            throw RoomServiceError.roomDecodeFailed(error.localizedDescription)
        }
    }

    // MARK: - Write: room_players / rooms

    func upsertMyState(
        roomId: UUID,
        meId: UUID,
        role: String,
        status: String,
        lat: Double?,
        lng: Double?,
        state: [String: AnyJSON]? = nil
    ) async throws {
        let nowISO = ISO8601DateFormatter().string(from: Date())

        var payload: [String: AnyJSON] = [
            "room_id": .string(roomId.uuidString.lowercased()),
            "user_id": .string(meId.uuidString.lowercased()),
            "role": .string(role),
            "status": .string(status),
            "updated_at": .string(nowISO),
        ]
        if let lat { payload["lat"] = .double(lat) }
        if let lng { payload["lng"] = .double(lng) }
        if let state { payload["state"] = .object(state) }

        _ = try await client
            .from("room_players")
            .upsert(payload, onConflict: "room_id,user_id")
            .execute()
    }

    func updateRoomStatus(roomId: UUID, status: String, winner: String? = nil) async throws {
        var payload: [String: AnyJSON] = [
            "status": .string(status)
        ]
        if let winner {
            payload["winner"] = .string(winner)
        }

        _ = try await client
            .from("rooms")
            .update(payload)
            .eq("id", value: roomId.uuidString.lowercased())
            .execute()
    }

    func updateRoom(roomId: UUID, patch: [String: AnyJSON]) async throws {
        _ = try await client
            .from("rooms")
            .update(patch)
            .eq("id", value: roomId.uuidString.lowercased())
            .execute()
    }

    func lockRoomRegion(roomId: UUID, regionId: UUID) async throws {
        let payload: [String: AnyJSON] = [
            "region_id": .string(regionId.uuidString.lowercased())
        ]

        _ = try await client
            .from("rooms")
            .update(payload)
            .eq("id", value: roomId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Realtime: room_players

    func subscribeRoomPlayers(roomId: UUID) async throws {
        if subscribedRoomId == roomId, channel != nil {
            DLog.warn("[RoomService] subscribeRoomPlayers ignored (already subscribed)")
            return
        }

        await unsubscribe()
        subscribedRoomId = roomId

        let chan = client.channel("room_players:\(roomId.uuidString)")
        self.channel = chan

        let stream = chan.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "room_players",
            filter: .eq("room_id", value: roomId.uuidString.lowercased())
        )

        changesTask = Task { [weak self] in
            guard let self else { return }
            for await change in stream {
                switch change {
                case .insert(let action):
                    self.handleUpsertRecord(action.record, tag: "INSERT")
                case .update(let action):
                    self.handleUpsertRecord(action.record, tag: "UPDATE")
                case .delete(let action):
                    self.handleDeleteRecord(action.oldRecord, tag: "DELETE")
                }
            }
        }

        _ = try await chan.subscribeWithError()
        DLog.ok("[RoomService] room_players subscribed OK")
    }

    func unsubscribe() async {
        changesTask?.cancel()
        changesTask = nil

        guard let channel else { return }

        await channel.unsubscribe()
        await client.removeChannel(channel)
        self.channel = nil

        DLog.ok("[RoomService] room_players channel removed")
    }

    // MARK: - Realtime: rooms

    func subscribeRoom(roomId: UUID) async throws {
        if subscribedRoomsId == roomId, roomChannel != nil {
            DLog.warn("[RoomService] subscribeRoom ignored (already subscribed)")
            return
        }

        await unsubscribeRoom()
        subscribedRoomsId = roomId

        let chan = client.channel("rooms:\(roomId.uuidString)")
        self.roomChannel = chan

        let stream = chan.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "rooms",
            filter: .eq("id", value: roomId.uuidString.lowercased())
        )

        roomChangesTask = Task { [weak self] in
            guard let self else { return }
            for await change in stream {
                switch change {
                case .insert(let action):
                    self.handleRoomUpsert(action.record, tag: "ROOM_INSERT")
                case .update(let action):
                    self.handleRoomUpsert(action.record, tag: "ROOM_UPDATE")
                case .delete:
                    DLog.warn("[RoomService] ROOM_DELETE received (ignored)")
                }
            }
        }

        _ = try await chan.subscribeWithError()
        DLog.ok("[RoomService] rooms subscribed OK")
    }

    func unsubscribeRoom() async {
        roomChangesTask?.cancel()
        roomChangesTask = nil

        guard let roomChannel else { return }

        await roomChannel.unsubscribe()
        await client.removeChannel(roomChannel)

        self.roomChannel = nil
        subscribedRoomsId = nil

        DLog.ok("[RoomService] rooms channel removed")
    }

    // MARK: - ✅ Sync: subscribe / broadcast / unsubscribe

    /// ✅ 订阅同步层：Broadcast(移动) + Presence(在线)
    func subscribeSync(roomId: UUID, meId: UUID) async throws {
        // ✅ 先清旧，避免 ghost
        await unsubscribeSync()

        onlineIds.removeAll()
        syncSubscribed = false
        didTrackOnce = false
        trackedMeId = meId

        let myKey = meId.uuidString.lowercased()

        let chan = client.channel("sync:\(roomId.uuidString)") {
            $0.broadcast.receiveOwnBroadcasts = true
            $0.broadcast.acknowledgeBroadcasts = true
            $0.presence.key = myKey          // ✅ 必须：presence key = userId
        }
        syncChannel = chan

        DLog.info("[RoomService] sync subscribing... topic=sync:\(roomId.uuidString) key=\(myKey)")

        // 1) Broadcast(move)
        moveSub = chan.onBroadcast(event: "move") { [weak self] json in
            guard let self else { return }
            do {
                let payload = try self.decodeMovePayload(from: json)
                self.emitMove(payload)
            } catch {
                DLog.warn("[RoomService] decode move payload failed: \(error.localizedDescription)")
            }
        }

        // 2) Presence：全量重建 + diff（保持你现有逻辑不变）
        presenceSub = chan.onPresenceChange { [weak self] action in
            guard let self else { return }

            let (joins, leaves) = Self.extractPresenceKeys(from: action)

            Task { @MainActor in
                let before = self.onlineIds

                // 🧠 经验判断：像 sync（presenceState）就全量重建
                let looksLikeSync = leaves.isEmpty && joins.count >= before.count

                if looksLikeSync {
                    self.onlineIds = Set(joins.compactMap { UUID(uuidString: $0) })
                } else {
                    for k in joins { if let id = UUID(uuidString: k) { self.onlineIds.insert(id) } }
                    for k in leaves { if let id = UUID(uuidString: k) { self.onlineIds.remove(id) } }
                }

                self.onPresenceSync?(self.onlineIds)

                DLog.info("""
                [RoomService] presence
                joins=\(joins.count) leaves=\(leaves.count)
                looksLikeSync=\(looksLikeSync)
                before=\(before.count) after=\(self.onlineIds.count)
                """)
            }
        }

        // 3) status：subscribed 时 track（只做一次），并标记 syncSubscribed
        syncStatusSub = chan.onStatusChange { [weak self] st in
            guard let self else { return }

            Task { @MainActor in
                DLog.info("[Sync DEBUG] status=\(st) didTrackOnce=\(self.didTrackOnce)")

                if st == .subscribed {
                    self.syncSubscribed = true

                    // ✅ 每次重新 subscribed 都要允许“重新 track 一次”
                    //    否则断网重连回不来
                    if self.didTrackOnce == false {
                        self.didTrackOnce = true

                        let payload: [String: AnyJSON] = [
                            "user_id": .string(myKey),
                            "platform": .string("ios")
                        ]

                        do {
                            try await chan.track(payload)
                            DLog.ok("[RoomService] presence track OK key=\(myKey)")
                        } catch {
                            DLog.warn("[RoomService] presence track FAILED: \(error.localizedDescription)")
                        }
                    }
                } else {
                    // 关键：只要离开 subscribed，就把 didTrackOnce 复位
                    // 这样下次回到 subscribed 才会再 track
                    self.syncSubscribed = false
                    self.didTrackOnce = false
                }
            }
        }

        // 4) subscribe
        _ = try await chan.subscribeWithError()
        DLog.ok("[RoomService] sync subscribeWithError returned ✅")
    }

    /// ✅ 广播移动（高频）
    func broadcastMove(meId: UUID, lat: Double, lng: Double, seq: Int) async {
        guard let syncChannel else { return }

        // ✅ 如果还没 subscribe 完，就不要发（否则会 fallback REST，未来会被废弃）
        guard syncSubscribed else {
            DLog.warn("[RoomService] broadcastMove skipped: sync not subscribed yet")
            return
        }

        let ts = ISO8601DateFormatter().string(from: Date())
        let msg = MovePayload(
            user_id: meId.uuidString.lowercased(),
            lat: lat,
            lng: lng,
            ts: ts,
            seq: seq
        )

        do {
            try await syncChannel.broadcast(event: "move", message: msg)
        } catch {
            DLog.warn("[RoomService] broadcastMove failed: \(error.localizedDescription)")
        }
    }

    /// ✅ 取消同步层订阅（离房必须调用）
    func unsubscribeSync() async {
        moveSub?.cancel(); moveSub = nil
        presenceSub?.cancel(); presenceSub = nil
        syncStatusSub?.cancel(); syncStatusSub = nil

        trackedMeId = nil
        onlineIds.removeAll()
        syncSubscribed = false
        didTrackOnce = false

        guard let chan = syncChannel else { return }

        // ⚠️ 网络断开时 untrack/unsubscribe 可能卡 or throw（保持你现有 fire-and-forget 行为）
        Task { await chan.untrack() }
        Task { await chan.unsubscribe() }

        await client.removeChannel(chan)
        syncChannel = nil

        DLog.ok("[RoomService] sync channel removed")
    }

    /// ⚠️ RoomService 是 @MainActor，static 默认也 MainActor 隔离；
    /// 这里必须 nonisolated，否则会报：
    /// “Call to main actor-isolated static method ... in a synchronous nonisolated context”
    nonisolated
    private static func extractPresenceKeys(
        from action: any PresenceAction
    ) -> (joins: [String], leaves: [String]) {

        var joins: [String] = []
        var leaves: [String] = []

        let mirror = Mirror(reflecting: action)
        for child in mirror.children {
            switch child.label {
            case "joins":
                if let dict = child.value as? [String: Any] {
                    joins = dict.keys.map { $0 }
                } else if let dict = child.value as? [String: PresenceV2] {
                    joins = dict.keys.map { $0 }
                }

            case "leaves":
                if let dict = child.value as? [String: Any] {
                    leaves = dict.keys.map { $0 }
                } else if let dict = child.value as? [String: PresenceV2] {
                    leaves = dict.keys.map { $0 }
                }

            default:
                break
            }
        }

        // 🔎 debug 时顺序稳定
        joins.sort()
        leaves.sort()

        return (joins, leaves)
    }

    // MARK: - Decode helpers: room_players

    private func handleUpsertRecord(_ record: [String: Any], tag: String) {
        guard let json = unwrapAnyJSON(record) as? [String: Any],
              JSONSerialization.isValidJSONObject(json)
        else {
            DLog.err("[RoomService][\(tag)] room_players record not valid JSON after unwrap keys=\(Array(record.keys))")
            debugDumpNonJSON(record, tag: tag)
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            let state = try isoDecoder.decode(RoomPlayerState.self, from: data)
            onUpsert?(state)
        } catch {
            DLog.err("[RoomService][\(tag)] room_players decode failed: \(error.localizedDescription)")
        }
    }

    private func handleDeleteRecord(_ record: [String: Any], tag: String) {
        guard let json = unwrapAnyJSON(record) as? [String: Any] else {
            DLog.err("[RoomService][\(tag)] delete record unwrap not dict")
            return
        }

        if let raw = json["user_id"] as? String, let id = UUID(uuidString: raw) {
            onDelete?(id)
        } else {
            DLog.err("[RoomService][\(tag)] missing user_id keys=\(Array(json.keys))")
        }
    }

    // MARK: - Decode helpers: rooms

    private func handleRoomUpsert(_ record: [String: Any], tag: String) {
        guard let json = unwrapAnyJSON(record) as? [String: Any],
              JSONSerialization.isValidJSONObject(json)
        else {
            DLog.err("[RoomService][\(tag)] rooms record not valid JSON after unwrap keys=\(Array(record.keys))")
            debugDumpNonJSON(record, tag: tag)
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            let room = try isoDecoder.decode(Room.self, from: data)
            onRoomUpdate?(room)
        } catch {
            DLog.err("[RoomService][\(tag)] rooms decode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - JSON decoder (ISO8601 兼容)

    private let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()

        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]

        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.timeZone = TimeZone(secondsFromGMT: 0)
        f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"

        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)

            if let dt = f1.date(from: s) { return dt }
            if let dt = f2.date(from: s) { return dt }
            if let dt = f3.date(from: s) { return dt }

            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Invalid date: \(s)"
            )
        }

        return d
    }()

    // MARK: - Rooms (Create)

    struct RoomInsertOut: Codable {
        let id: UUID
    }

    func createRoom(
        createdBy: UUID,
        status: String = "waiting",
        regionId: UUID? = nil,
        rule: [String: AnyJSON] = [:]
    ) async throws -> UUID {
        var payload: [String: AnyJSON] = [
            "status": .string(status),
            "rule": .object(rule),
            "created_by": .string(createdBy.uuidString.lowercased()),
        ]

        if let regionId {
            payload["region_id"] = .string(regionId.uuidString.lowercased())
        }

        let res = try await client
            .from("rooms")
            .insert(payload)
            .select("id")
            .single()
            .execute()

        let out = try isoDecoder.decode(RoomInsertOut.self, from: res.data)
        return out.id
    }

    func removeMeFromRoom(roomId: UUID, meId: UUID) async throws {
        _ = try await client
            .from("room_players")
            .delete()
            .eq("room_id", value: roomId.uuidString.lowercased())
            .eq("user_id", value: meId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Debug helpers

    private func debugDumpNonJSON(_ record: [String: Any], tag: String) {
        for (k, v) in record {
            let ok: Bool = {
                if v is String { return true }
                if v is NSNumber { return true }
                if v is NSNull { return true }
                if v is [Any] { return true }
                if v is [String: Any] { return true }
                return false
            }()

            if !ok {
                let typeName = String(describing: Swift.type(of: v))
                DLog.err("[RoomService][\(tag)] NON-JSON key=\(k) type=\(typeName) value=\(String(describing: v))")
            }
        }
    }

    private func unwrapAnyJSON(_ v: Any) -> Any {
        if let a = v as? AnyJSON { return a.value }

        if let dict = v as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, vv) in dict { out[k] = unwrapAnyJSON(vv) }
            return out
        }
        if let arr = v as? [Any] {
            return arr.map(unwrapAnyJSON)
        }

        let m = Mirror(reflecting: v)
        if m.displayStyle == .optional {
            if let child = m.children.first {
                return unwrapAnyJSON(child.value)
            }
            return NSNull()
        }

        return v
    }

    // MARK: - RPC

    func attemptTag(roomId: UUID, targetUserId: UUID) async throws -> AttemptTagResult {
        let params: [String: String] = [
            "p_room_id": roomId.uuidString.lowercased(),
            "p_target_user": targetUserId.uuidString.lowercased(),
        ]

        let res = try await client
            .rpc("attempt_tag", params: params)
            .execute()

        return try JSONDecoder().decode(AttemptTagResult.self, from: res.data)
    }

    // MARK: - DEBUG (opt-in; does not affect business logic)

    #if DEBUG
    @MainActor
    func forceTrackDebug(meId: UUID) async {
        guard let syncChannel else {
            DLog.warn("[DEBUG] forceTrackDebug: syncChannel is nil")
            return
        }

        let myKey = meId.uuidString.lowercased()
        let payload: [String: AnyJSON] = [
            "user_id": .string(myKey),
            "platform": .string("ios"),
            "debug": .string("forceTrack")
        ]

        do {
            try await syncChannel.track(payload)
            DLog.ok("[DEBUG] forceTrackDebug: track OK key=\(myKey)")
        } catch {
            DLog.warn("[DEBUG] forceTrackDebug: track FAILED \(error.localizedDescription)")
        }
    }
    #endif
}

// MARK: - AttemptTagResult

public struct AttemptTagResult: Decodable, Sendable {
    public let ok: Bool
    public let reason: String?
    public let dist_m: Double?
    public let remaining_runners: Int?
    public let room_status: String?
    public let target_status: String?
    public let game_ended: Bool?
}
