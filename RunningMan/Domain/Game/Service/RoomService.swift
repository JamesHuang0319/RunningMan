//
//  RoomService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//
//

import Foundation
import Supabase

@MainActor
final class RoomService {

    struct Config {
        var upsertMeOnJoin: Bool = true
    }

    enum RoomServiceError: LocalizedError {
        case missingUserId
        case decodeFailed(String)

        // ✅ MOD: rooms realtime 相关错误
        case missingRoomId
        case roomDecodeFailed(String)

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
            }
        }
    }

    // MARK: - Dependencies
    private let client: SupabaseClient
    private let config: Config

    // MARK: - Realtime: room_players (✅ 2.39.0 使用 V2)
    private var channel: RealtimeChannelV2?
    private var changesTask: Task<Void, Never>?
    private(set) var subscribedRoomId: UUID?

    // MARK: - Rooms Realtime (✅ MOD: rooms 表订阅)
    private var roomChannel: RealtimeChannelV2?
    private var roomChangesTask: Task<Void, Never>?
    private(set) var subscribedRoomsId: UUID?  // ✅ MOD
    private var onRoomUpdate: ((Room) -> Void)?

    func setRoomCallback(onUpdate: @escaping (Room) -> Void) {
        self.onRoomUpdate = onUpdate
    }

    // MARK: - Callbacks (room_players)
    private var onUpsert: ((RoomPlayerState) -> Void)?
    private var onDelete: ((UUID) -> Void)?

    init(
        client: SupabaseClient = SupabaseClientProvider.shared.client,
        config: Config = .init()
    ) {
        self.client = client
        self.config = config
    }

    func setRoomPlayersCallbacks(
        onUpsert: @escaping (RoomPlayerState) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.onUpsert = onUpsert
        self.onDelete = onDelete
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

        DLog.info(
            "[RoomService] joinRoom started: roomId=\(roomId.uuidString), meId=\(meId.uuidString)"
        )

        // ✅ 1) 先订阅 realtime，避免 snapshot 与订阅之间漏事件
        DLog.info(
            "[RoomService] Subscribing to room players changes for roomId=\(roomId.uuidString)..."
        )
        try await subscribeRoomPlayers(roomId: roomId)
        DLog.info(
            "[RoomService] Successfully subscribed to room players changes for roomId=\(roomId.uuidString)"
        )

        // ✅ 2) 再拉 snapshot
        DLog.info(
            "[RoomService] Fetching room players for roomId=\(roomId.uuidString)..."
        )
        var snapshot = try await fetchRoomPlayers(roomId: roomId)
        DLog.info(
            "[RoomService] fetched room players snapshot: \(snapshot.count) players"
        )

        // ✅ 3) upsert 自己（可选）
        if config.upsertMeOnJoin {
            DLog.info(
                "[RoomService] Upserting current player's state in the room..."
            )
            try await upsertMyState(
                roomId: roomId,
                meId: meId,
                role: initialRole,
                status: initialStatus,
                lat: nil,
                lng: nil
            )
            DLog.info(
                "[RoomService] Successfully upserted current player's state."
            )

            // ✅ 推荐：再拉一次 snapshot，确保包含我最新状态（最稳，代价是多一次 select）
            snapshot = try await fetchRoomPlayers(roomId: roomId)
            DLog.info(
                "[RoomService] refetched snapshot after upsert: \(snapshot.count) players"
            )
        }

        DLog.info(
            "[RoomService] joinRoom completed successfully for roomId=\(roomId.uuidString)"
        )
        return snapshot
    }

    func leaveRoom() async {
        DLog.warn(
            "[RoomService] leaveRoom roomId=\(subscribedRoomId?.uuidString ?? "-")"
        )

        await unsubscribe()
        await unsubscribeRoom()  // ✅ MOD: 离房同时取消 rooms 订阅

        subscribedRoomId = nil
    }

    // MARK: - Snapshot: room_players

    func fetchRoomPlayers(roomId: UUID) async throws -> [RoomPlayerState] {
        do {
            let res =
                try await client
                .from("room_players")
                .select()
                .eq("room_id", value: roomId.uuidString.lowercased())
                .execute()

            do {
                return try isoDecoder.decode(
                    [RoomPlayerState].self,
                    from: res.data
                )
            } catch {
                throw RoomServiceError.decodeFailed(error.localizedDescription)
            }
        } catch {
            DLog.err(
                "[RoomService] fetchRoomPlayers failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

    // MARK: - Snapshot: rooms (你已实现)
    func fetchRoom(roomId: UUID) async throws -> Room {
        let res =
            try await client
            .from("rooms")
            .select()
            .eq("id", value: roomId.uuidString.lowercased())
            .single()
            .execute()

        // 打印返回的数据类型和内容
        DLog.info(
            "[RoomService] fetchRoom response type: \(type(of: res.data))"
        )

        // 打印原始返回的 JSON 数据
        if let jsonString = String(data: res.data, encoding: .utf8) {
            DLog.info("[RoomService] fetchRoom response content: \(jsonString)")
        } else {
            DLog.err(
                "[RoomService] fetchRoom: Failed to convert data to string"
            )
        }

        // 尝试解码数据
        do {
            return try isoDecoder.decode(Room.self, from: res.data)
        } catch {
            DLog.err(
                "[RoomService] fetchRoom decode failed: \(error.localizedDescription)"
            )

            // 打印原始数据，帮助进一步诊断问题
            if let jsonString = String(data: res.data, encoding: .utf8) {
                DLog.err("[RoomService] fetchRoom raw data: \(jsonString)")
            } else {
                DLog.err(
                    "[RoomService] fetchRoom raw data: Unable to convert to string"
                )
            }

            throw RoomServiceError.roomDecodeFailed(error.localizedDescription)
        }
    }

    // MARK: - Write: room_players

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

        DLog.info(
            "[RoomService] upsertMyState role=\(role) status=\(status) lat=\(lat?.description ?? "nil") lng=\(lng?.description ?? "nil") updated_at=\(nowISO)"
        )

        _ =
            try await client
            .from("room_players")
            .upsert(payload, onConflict: "room_id,user_id")
            .execute()
    }



    // MARK: - Write: rooms

    /// ✅ MOD: 房主更新房间状态 (支持写入 winner)
    /// - Parameters:
    ///   - winner: 可选。传入 "hunters" / "runners"。如果不传(nil)，则不更新该字段（保持 NULL）。
    func updateRoomStatus(roomId: UUID, status: String, winner: String? = nil)
        async throws
    {
        DLog.info(
            "[RoomService] updateRoomStatus roomId=\(roomId) status=\(status) winner=\(winner ?? "nil")"
        )

        // 1. 构建 payload
        var payload: [String: AnyJSON] = [
            "status": .string(status)
        ]

        // 2. 如果有 winner，写入 payload
        if let winner = winner {
            payload["winner"] = .string(winner)
        }
        // 注意：如果你想显式把 winner 设为 NULL（例如撤销胜利），可以用 payload["winner"] = .null
        // 但在这个场景下，没传 winner 就代表“无胜负/中止”，不传 key 即可。

        // 3. 发送请求
        _ =
            try await client
            .from("rooms")
            .update(payload)
            .eq("id", value: roomId.uuidString.lowercased())
            .execute()
    }
    
    // ✅ MOD: 可选：通用 rooms patch 更新（不替换你现有两个函数）
    func updateRoom(roomId: UUID, patch: [String: AnyJSON]) async throws {
        DLog.info(
            "[RoomService] updateRoom roomId=\(roomId.uuidString) patchKeys=\(Array(patch.keys))"
        )
        _ =
            try await client
            .from("rooms")
            .update(patch)
            .eq("id", value: roomId.uuidString.lowercased())
            .execute()
    }

    /// ✅ MOD: 房主锁定区域：更新 rooms.region_id
    func lockRoomRegion(roomId: UUID, regionId: UUID) async throws {
        let payload: [String: AnyJSON] = [
            "region_id": .string(regionId.uuidString.lowercased())
        ]

        let res =
            try await client
            .from("rooms")
            .update(payload)
            .eq("id", value: roomId.uuidString.lowercased())
            .select("id, region_id, created_by")
            .single()
            .execute()

        if let s = String(data: res.data, encoding: .utf8) {
            DLog.info("[RoomService] lockRoomRegion result: \(s)")
        }
    }

    // MARK: - Realtime: room_players

    func subscribeRoomPlayers(roomId: UUID) async throws {
        if subscribedRoomId == roomId, channel != nil {
            DLog.warn(
                "[RoomService] subscribeRoomPlayers ignored (already subscribed)"
            )
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
            DLog.info("[RoomService] room_players changesTask started")

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

            DLog.warn("[RoomService] room_players changesTask ended")
        }

        DLog.info("[RoomService] subscribing room_players...")
        do {
            _ = try await chan.subscribeWithError()
            DLog.ok("[RoomService] room_players subscribed OK")
        } catch {
            DLog.err(
                "[RoomService] room_players subscribe threw: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func unsubscribe() async {
        changesTask?.cancel()
        changesTask = nil

        guard let channel else { return }

        DLog.warn("[RoomService] unsubscribing room_players...")
        await channel.unsubscribe()
        await client.removeChannel(channel)

        self.channel = nil
        DLog.ok("[RoomService] room_players channel removed")
    }

    // MARK: - Realtime: rooms (✅ MOD: 订阅 rooms 表，驱动 Lobby/Playing 等)

    /// ✅ MOD: 订阅 rooms 表的变更（同一个 roomId）
    func subscribeRoom(roomId: UUID) async throws {
        if subscribedRoomsId == roomId, roomChannel != nil {
            DLog.warn(
                "[RoomService] subscribeRoom ignored (already subscribed)"
            )
            return
        }

        await unsubscribeRoom()
        subscribedRoomsId = roomId

        let chan = client.channel("rooms:\(roomId.uuidString)")
        self.roomChannel = chan

        // 只监听这一个房间 id
        let stream = chan.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "rooms",
            filter: .eq("id", value: roomId.uuidString.lowercased())
        )

        roomChangesTask = Task { [weak self] in
            guard let self else { return }
            DLog.info("[RoomService] rooms changesTask started")

            for await change in stream {
                switch change {
                case .insert(let action):
                    self.handleRoomUpsert(action.record, tag: "ROOM_INSERT")
                case .update(let action):
                    self.handleRoomUpsert(action.record, tag: "ROOM_UPDATE")
                case .delete(let action):
                    // rooms 通常不 delete；如果你真的 delete 房间，也可以在这里处理
                    DLog.warn("[RoomService] ROOM_DELETE received (ignored)")
                }
            }

            DLog.warn("[RoomService] rooms changesTask ended")
        }

        DLog.info("[RoomService] subscribing rooms...")
        do {
            _ = try await chan.subscribeWithError()
            DLog.ok("[RoomService] rooms subscribed OK")
        } catch {
            DLog.err(
                "[RoomService] rooms subscribe threw: \(error.localizedDescription)"
            )
            throw error
        }
    }

    /// ✅ MOD: 取消订阅 rooms
    func unsubscribeRoom() async {
        roomChangesTask?.cancel()
        roomChangesTask = nil

        guard let roomChannel else { return }

        DLog.warn("[RoomService] unsubscribing rooms...")
        await roomChannel.unsubscribe()
        await client.removeChannel(roomChannel)

        self.roomChannel = nil
        subscribedRoomsId = nil
        DLog.ok("[RoomService] rooms channel removed")
    }

    // MARK: - Decode helpers: room_players

    private func handleUpsertRecord(_ record: [String: Any], tag: String) {
        guard let json = unwrapAnyJSON(record) as? [String: Any],
            JSONSerialization.isValidJSONObject(json)
        else {
            DLog.err(
                "[RoomService][\(tag)] room_players record not valid JSON after unwrap keys=\(Array(record.keys))"
            )
            debugDumpNonJSON(record, tag: tag)
            return
        }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: json,
                options: []
            )
            let state = try isoDecoder.decode(RoomPlayerState.self, from: data)
            onUpsert?(state)
        } catch {
            DLog.err(
                "[RoomService][\(tag)] room_players decode failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleDeleteRecord(_ record: [String: Any], tag: String) {
        guard let json = unwrapAnyJSON(record) as? [String: Any] else {
            DLog.err("[RoomService][\(tag)] delete record unwrap not dict")
            return
        }

        if let raw = json["user_id"] as? String, let id = UUID(uuidString: raw)
        {
            onDelete?(id)
        } else {
            DLog.err(
                "[RoomService][\(tag)] missing user_id keys=\(Array(json.keys))"
            )
        }
    }

    // MARK: - Decode helpers: rooms (✅ MOD)

    private func handleRoomUpsert(_ record: [String: Any], tag: String) {
        guard let json = unwrapAnyJSON(record) as? [String: Any],
            JSONSerialization.isValidJSONObject(json)
        else {
            DLog.err(
                "[RoomService][\(tag)] rooms record not valid JSON after unwrap keys=\(Array(record.keys))"
            )
            debugDumpNonJSON(record, tag: tag)
            return
        }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: json,
                options: []
            )
            let room = try isoDecoder.decode(Room.self, from: data)
            DLog.info(
                "[RoomService] \(tag) roomId=\(room.id.uuidString) status=\(room.status) regionId=\(room.regionId?.uuidString ?? "nil")"
            )
            onRoomUpdate?(room)
        } catch {
            DLog.err(
                "[RoomService][\(tag)] rooms decode failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - JSON decoder

    private let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()

        // 兼容 iOS17/18：同时支持
        // 1) 2025-12-26T11:34:19Z
        // 2) 2025-12-26T11:34:19.824Z
        // 3) 2025-12-26T11:34:19.824761+00:00  <- 你现在这种
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]

        // 兜底：手动格式（支持 +00:00）
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

    // MARK: - Rooms (P0: create)

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
            "rule": .object(rule),  // rooms.rule NOT NULL
            "created_by": .string(createdBy.uuidString.lowercased()),
        ]

        if let regionId {
            payload["region_id"] = .string(regionId.uuidString.lowercased())
        }

        DLog.info(
            "[RoomService] createRoom inserting... status=\(status) created_by=\(createdBy.uuidString) region_id=\(regionId?.uuidString ?? "nil")"
        )

        let res =
            try await client
            .from("rooms")
            .insert(payload)
            .select("id")
            .single()
            .execute()

        let out = try isoDecoder.decode(RoomInsertOut.self, from: res.data)
        DLog.ok("[RoomService] createRoom ok id=\(out.id.uuidString)")
        return out.id
    }

    // ✅ 供 GameStore.leaveRoom() 调用：离房时把自己那行删掉
    func removeMeFromRoom(roomId: UUID, meId: UUID) async throws {
        DLog.warn(
            "[RoomService] removeMeFromRoom roomId=\(roomId.uuidString) meId=\(meId.uuidString)"
        )
        _ =
            try await client
            .from("room_players")
            .delete()
            .eq("room_id", value: roomId.uuidString.lowercased())
            .eq("user_id", value: meId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Debug helpers (保留你的)

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
                DLog.err(
                    "[RoomService][\(tag)] NON-JSON key=\(k) type=\(typeName) value=\(String(describing: v))"
                )
            }
        }
    }

    private func unwrapAnyJSON(_ v: Any) -> Any {
        // ✅ Supabase AnyJSON：一行搞定
        if let a = v as? AnyJSON { return a.value }

        // ✅ 容器递归：把容器里可能出现的 AnyJSON 也 unwrap 掉
        if let dict = v as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, vv) in dict { out[k] = unwrapAnyJSON(vv) }
            return out
        }
        if let arr = v as? [Any] {
            return arr.map(unwrapAnyJSON)
        }

        // ✅ Optional 兜底
        let m = Mirror(reflecting: v)
        if m.displayStyle == .optional {
            if let child = m.children.first {
                return unwrapAnyJSON(child.value)
            }
            return NSNull()
        }

        // ✅ 其它值保持原样
        return v
    }

    // MARK: - RPC (Game Actions)

    /// ✅ 猎人尝试抓捕逃跑者（服务器原子判定）
    /// - Parameters:
    ///   - roomId: 房间 id
    ///   - targetUserId: 被抓的 runner id
    /// - Returns: AttemptTagResult，包含 ok/reason/距离/剩余runner等
    func attemptTag(roomId: UUID, targetUserId: UUID) async throws
        -> AttemptTagResult
    {
        DLog.info(
            "[RoomService] attemptTag calling rpc room=\(roomId) target=\(targetUserId)"
        )

        // ✅ 用 Dictionary 规避 Swift 6 MainActor 默认隔离导致的 Encodable/Sendable 冲突
        let params: [String: String] = [
            "p_room_id": roomId.uuidString.lowercased(),
            "p_target_user": targetUserId.uuidString.lowercased(),
        ]

        let res =
            try await client
            .rpc("attempt_tag", params: params)
            .execute()

        if let s = String(data: res.data, encoding: .utf8) {
            DLog.info("[RPC attempt_tag] raw: \(s)")
        }

        return try JSONDecoder().decode(AttemptTagResult.self, from: res.data)
    }

}

public struct AttemptTagResult: Decodable, Sendable {
    public let ok: Bool
    public let reason: String?
    public let dist_m: Double?
    public let remaining_runners: Int?

    // ✅ 对应 SQL 中的 room_status / target_status (如果 SQL 返回了)
    public let room_status: String?
    public let target_status: String?

    // ✅ 新增：对应 SQL 中的 game_ended
    public let game_ended: Bool?
}
