//
//  ProfileService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import Foundation
import Supabase

final class ProfileService {

    // MARK: - Dependencies
    private let supabase = SupabaseClientProvider.shared.client
    let bucket = "avatars"

    // MARK: - Data Structures

    /// 用于批量拉取时的返回结构
    struct ProfileInfo {
        let name: String
        let avatarDownloadURL: URL?
        let avatarPath: String?
    }

    // MARK: - Helpers

    /// ✅ 版本化存储路径： "<uid>/avatar_<unix>.jpg"
    /// - 目的：避免同名覆盖导致 CDN/客户端缓存返回旧图
    func avatarPath(for uid: UUID) -> String {
        let v = Int(Date().timeIntervalSince1970)
        return "\(uid.uuidString.lowercased())/avatar_\(v).jpg"
    }

    // MARK: - Profile Core (Fetch & Upsert)

    /// 拉取单个 Profile
    /// - 只有「确实没行」才返回默认壳数据；其它网络/鉴权错误一律 throw
    func fetchProfile(userId uid: UUID) async throws -> ProfileRow {
        DLog.info("[ProfileService] fetchProfile start uid=\(uid)")

        do {
            // ✅ select() 会自动查询所有字段，并且通过 user_achievements(*) 嵌套查询成就
            let row: ProfileRow =
                try await supabase
                .from("profiles")
                .select("*, user_achievements(*)")  // 👈 关键修改：一次性查两张表
                .eq("id", value: uid)
                .single()
                .execute()
                .value

            DLog.ok(
                "[ProfileService] fetchProfile success uid=\(uid) avatar=\(row.avatarURL ?? "nil")"
            )
            return row

        } catch {
            let msg = String(describing: error)

            // 处理 406 Not Acceptable 或 No Rows 错误，返回默认数据
            if msg.contains("406")
                || msg.localizedCaseInsensitiveContains("no rows")
            {
                DLog.warn(
                    "[ProfileService] fetchProfile no rows uid=\(uid) -> return default shell"
                )

                // ✅ 修复：必须初始化所有字段，包括统计数据和新增的成就字段
                return ProfileRow(
                    id: uid,
                    username: "Player\(uid.uuidString.prefix(4))",
                    fullName: nil,
                    avatarURL: nil,
                    totalGames: 0,  // 默认值
                    totalWins: 0,  // 默认值
                    totalDistance: 0.0,  // 默认值
                    userAchievements: []  // 默认空数组
                )
            }

            DLog.err(
                "[ProfileService] fetchProfile failed uid=\(uid) err=\(error)"
            )
            throw error
        }
    }

    /// 更新/插入 Profile
    func upsertProfile(_ profile: ProfileRow) async throws {
        DLog.info(
            "[ProfileService] upsertProfile start id=\(profile.id) username=\(profile.username ?? "nil")"
        )

        do {
            try await supabase
                .from("profiles")
                .upsert(profile)
                .execute()

            DLog.ok("[ProfileService] upsertProfile success id=\(profile.id)")
        } catch {
            DLog.err(
                "[ProfileService] upsertProfile failed id=\(profile.id) err=\(error)"
            )
            throw error
        }
    }

    // MARK: - Avatar Management (Storage)

    /// 上传头像（JPEG）到 Storage，返回 path（不是 URL）
    func uploadAvatarJPEG(userId uid: UUID, jpegData: Data) async throws
        -> String
    {
        let path = avatarPath(for: uid)
        DLog.info(
            "[ProfileService] uploadAvatarJPEG start uid=\(uid) path=\(path) bytes=\(jpegData.count)"
        )

        do {
            try await supabase.storage
                .from(bucket)
                .upload(
                    path,
                    data: jpegData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: false  // ✅ 版本化路径，不需要覆盖
                    )
                )

            DLog.ok("[ProfileService] uploadAvatarJPEG success path=\(path)")
            return path

        } catch {
            DLog.err(
                "[ProfileService] uploadAvatarJPEG failed path=\(path) err=\(error)"
            )
            throw error
        }
    }

    /// 获取 Signed URL (用于私有桶访问)
    func signedAvatarURL(for path: String, expiresIn seconds: Int = 60 * 10)
        async throws -> URL
    {
        // DLog.info("[ProfileService] signedAvatarURL start path=\(path)") // 可选：减少日志噪音

        do {
            let url = try await supabase.storage
                .from(bucket)
                .createSignedURL(path: path, expiresIn: seconds)

            // DLog.ok("[ProfileService] signedAvatarURL success")
            return url

        } catch {
            DLog.err(
                "[ProfileService] signedAvatarURL failed path=\(path) err=\(error)"
            )
            throw error
        }
    }

    // MARK: - Batch Operations (Map/List Support)

    /// 基础批量拉取：仅获取数据库行信息
    func fetchProfiles(ids: [UUID]) async throws -> [ProfileRow] {
        guard !ids.isEmpty else { return [] }
        DLog.info(
            "[ProfileService] fetchProfiles batch start count=\(ids.count)"
        )

        do {
            let rows: [ProfileRow] =
                try await supabase
                .from("profiles")
                .select()
                .in("id", value: ids)
                .execute()
                .value
            return rows
        } catch {
            DLog.err("[ProfileService] fetchProfiles batch failed: \(error)")
            return []
        }
    }

    /// ✅ 终极方法：批量拉取资料 + 并发签名头像
    /// 返回字典：[UserID : ProfileInfo]
    func fetchProfilesAndSignAvatars(ids: [UUID]) async -> [UUID: ProfileInfo] {
        // 1. 先从数据库批量查人
        let rows = try? await fetchProfiles(ids: ids)
        guard let rows = rows, !rows.isEmpty else { return [:] }

        // 2. 使用 TaskGroup 并行处理头像签名 (速度快)
        return await withTaskGroup(of: (UUID, ProfileInfo).self) { group in
            for row in rows {
                group.addTask {
                    let name = row.username ?? "神秘特工"
                    var downloadURL: URL? = nil
                    let storagePath = row.avatarURL

                    // 如果有头像路径，尝试签名
                    if let path = storagePath, !path.isEmpty {
                        do {
                            // 调用现有的签名逻辑，有效期设长一点，比如 1小时
                            downloadURL = try await self.signedAvatarURL(
                                for: path,
                                expiresIn: 3600
                            )
                        } catch {
                            print(
                                "⚠️ Avatar sign failed for \(row.id): \(error)"
                            )
                        }
                    }

                    let info = ProfileInfo(
                        name: name,
                        avatarDownloadURL: downloadURL,
                        avatarPath: storagePath
                    )
                    return (row.id, info)
                }
            }

            // 3. 收集结果
            var result: [UUID: ProfileInfo] = [:]
            for await (uid, info) in group {
                result[uid] = info
            }
            return result
        }
    }

    // MARK: - Achievements System

    /// 从数据库拉取所有成就定义配置 (Metadata)
    func fetchAchievementDefinitions() async throws -> [AchievementDefinition] {
        DLog.info("[ProfileService] fetchAchievementDefinitions start")

        do {
            let defs: [AchievementDefinition] =
                try await supabase
                .from("achievement_definitions")
                .select()
                .execute()
                .value

            DLog.ok("[ProfileService] fetched \(defs.count) definitions")
            return defs
        } catch {
            DLog.err(
                "[ProfileService] fetchAchievementDefinitions failed: \(error)"
            )
            throw error
        }
    }

    /// 拉取用户获得的所有成就
    func fetchAchievements(userId: UUID) async throws -> [UserAchievementRow] {
        let rows: [UserAchievementRow] =
            try await supabase
            .from("user_achievements")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        return rows
    }

    /// 删除成就 (对应 UI 的“管理-删除”功能)
    func deleteAchievement(id: Int) async throws {
        try await supabase
            .from("user_achievements")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// 添加成就 (仅供测试或结算时调用)
    func addAchievement(userId: UUID, type: String) async throws {
        struct Payload: Encodable {
            let user_id: UUID
            let type: String
        }
        try await supabase
            .from("user_achievements")
            .insert(Payload(user_id: userId, type: type))
            .execute()
    }

    func updateAchievementVisibility(id: Int, isHidden: Bool) async throws {
        // 这里负责具体的 SQL 构建
        try await supabase
            .from("user_achievements")
            .update(["is_hidden": isHidden])  // 对应数据库字段
            .eq("id", value: id)
            .execute()
    }


    /// 通用局部更新方法
    /// - Parameters:
    ///   - userId: 用户 ID
    ///   - updates: 需要更新的字段字典 (例如 ["username": "NewName"])
    func updateProfileFields(userId: UUID, updates: [String: String])
        async throws
    {
        try await supabase
            .from("profiles")
            .update(updates)  // ⚠️ update 只修改指定字段，不动其他字段
            .eq("id", value: userId)
            .execute()
    }
}
