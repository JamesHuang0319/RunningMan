//
//  ProfileStore.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/24.
//

import Foundation
import Observation
import Kingfisher

@Observable
final class ProfileStore {

    private let service: ProfileService

    // MARK: - State

    /// 当前登录用户的 profile（只存一份，供 UI 使用）
    var me: ProfileRow?

    /// loading 状态（可用于页面骨架）
    var isLoadingMe: Bool = false

    /// 最近一次错误（用于 UI 展示）
    var error: String?

    /// 多用户缓存：好友/地图等场景会用到
    var profilesById: [UUID: ProfileRow] = [:]

    // MARK: - Signed URL Cache

    /// Signed URL 会变化且会过期，但 KF 缓存 key 必须稳定。
    /// 我们约定：缓存 key = Storage path（例如 "<uid>/avatar_123.jpg"）
    struct SignedURLCacheItem {
        let url: URL
        let expiresAt: Date
    }

    private(set) var avatarURLByPath: [String: SignedURLCacheItem] = [:]

    /// Signed URL 有效期：需与 ProfileService.signedAvatarURL(expiresIn:) 对齐
    private let signedURLTTL: TimeInterval = 60 * 10

    /// 临期阈值：剩余不到 refreshLeeway 秒就刷新
    private let refreshLeeway: TimeInterval = 60

    // MARK: - Persistence (UserDefaults)

    /// 持久化 “me 的快照”，用于冷启动先显示（头像可命中磁盘缓存）
    private struct PersistedMe: Codable {
        let id: UUID
        let username: String?
        let fullName: String?
        let avatarURL: String?   // 存 storage path
        let savedAt: Date
    }

    private let persistedMeKey = "profile.persisted.me.v1"

    // MARK: - Bootstrap control

    private var bootstrappedUserId: UUID?

    init(service: ProfileService = ProfileService()) {
        self.service = service
        DLog.info("[ProfileStore] init")
    }

    // MARK: - Public helpers (for View)

    /// View 用：通过 path 获取可用 signed URL（不存在/过期则 nil）
    func signedURL(forPath path: String) -> URL? {
        guard let item = avatarURLByPath[path] else { return nil }
        if item.expiresAt <= Date() { return nil }
        return item.url
    }

    /// View 用：从 profile 拿到头像 storage path（稳定 key）
    func avatarPath(for profile: ProfileRow) -> String? {
        profile.avatarURL
    }

    /// 通过 uid 拿到头像 storage path
    func avatarPath(for uid: UUID) -> String? {
        profilesById[uid]?.avatarURL
    }

    // MARK: - Bootstrap (call at RootView)

    /// ✅ 登录后在 RootView 调用一次：
    /// 1) 先恢复本地快照（让 UI 秒出）
    /// 2) 再后台拉云端刷新（更新用户名/头像 path 等）
    @MainActor
    func bootstrapIfNeeded(userId: UUID) async {
        guard bootstrappedUserId != userId else { return }
        bootstrappedUserId = userId

        // 1) 先用本地
        restorePersistedMeIfPossible(for: userId)

        // 2) 再刷新云端（不再重复从本地恢复）
        await loadMe(userId: userId, usePersistedFirst: false)
    }

    // MARK: - Load current user profile

    /// 拉取当前用户 profile，并确保头像 signed URL 可用
    ///
    /// - Parameters:
    ///   - userId: 当前用户 id
    ///   - forceRefreshAvatar: true 时强制刷新 signedURL（用于手动刷新/诊断）
    ///   - clearImageCacheIfForce: true 时可清 KF 缓存（通常版本化 path 后不需要）
    ///   - usePersistedFirst: true 时会先尝试 restore 本地快照（兜底用）
    @MainActor
    func loadMe(
        userId: UUID,
        forceRefreshAvatar: Bool = false,
        clearImageCacheIfForce: Bool = false,
        usePersistedFirst: Bool = true
    ) async {
        error = nil
        isLoadingMe = true
        defer { isLoadingMe = false }

        if usePersistedFirst, me?.id != userId {
            restorePersistedMeIfPossible(for: userId)
        }

        DLog.info("[ProfileStore] loadMe start uid=\(userId) forceRefreshAvatar=\(forceRefreshAvatar)")

        do {
            let oldPath = profilesById[userId]?.avatarURL

            let p = try await service.fetchProfile(userId: userId)
            me = p
            profilesById[userId] = p

            // ✅ 持久化最新 me（下次冷启动先用它）
            persistMe(p)

            if let newPath = p.avatarURL {
                let pathChanged = (oldPath != newPath)

                if (forceRefreshAvatar || pathChanged), clearImageCacheIfForce {
                    clearKingfisherCache(forPath: newPath)
                }

                // path 变化或 force 时刷新 signed URL
                await refreshAvatarURL(path: newPath, force: forceRefreshAvatar || pathChanged)
            }

            DLog.ok("[ProfileStore] loadMe success uid=\(userId) avatar=\(p.avatarURL ?? "nil")")
        } catch {
            self.error = error.localizedDescription
            DLog.err("[ProfileStore] loadMe failed uid=\(userId) err=\(error)")
        }
    }

    // MARK: - Batch load (friends / map)

    func loadProfiles(userIds: [UUID]) async {
        DLog.info("[ProfileStore] loadProfiles start count=\(userIds.count)")

        for uid in userIds {
            if profilesById[uid] != nil { continue }

            do {
                let p = try await service.fetchProfile(userId: uid)
                profilesById[uid] = p

                if let path = p.avatarURL {
                    await refreshAvatarURL(path: path, force: false)
                }

                DLog.ok("[ProfileStore] loadProfiles cached uid=\(uid) avatar=\(p.avatarURL ?? "nil")")
            } catch {
                DLog.warn("[ProfileStore] loadProfiles failed uid=\(uid) err=\(error)")
            }
        }

        DLog.ok("[ProfileStore] loadProfiles done")
    }

    // MARK: - Update avatar (versioned path)

    /// 更新头像：
    /// - 版本化 path（avatar_<unix>.jpg） => 天然绕过 CDN/客户端缓存
    /// - 旧文件允许存在（你选的 B）
    func updateMyAvatar(userId: UUID, jpegData: Data) async {
        error = nil
        DLog.info("[ProfileStore] updateMyAvatar start uid=\(userId) bytes=\(jpegData.count)")

        do {
            // 1) 上传 Storage：生成新 path（版本化）
            let path = try await service.uploadAvatarJPEG(userId: userId, jpegData: jpegData)

            // 2) 写回 DB：profiles.avatar_url = 新 path
            var p = (me ?? profilesById[userId]) ?? ProfileRow(
                id: userId,
                username: nil,
                fullName: nil,
                avatarURL: nil
            )
            p.avatarURL = path
            try await service.upsertProfile(p)

            // 3) 写回内存缓存（主线程更新观察状态）
            await MainActor.run {
                me = p
                profilesById[userId] = p
            }

            // ✅ 持久化，保证下次启动直接展示新头像
            persistMe(p)

            // 4) 生成/刷新 signed URL（新 path 基本必然是新条目）
            await refreshAvatarURL(path: path, force: true)

            DLog.ok("[ProfileStore] updateMyAvatar success uid=\(userId) path=\(path)")
        } catch {
            self.error = error.localizedDescription
            DLog.err("[ProfileStore] updateMyAvatar failed uid=\(userId) err=\(error)")
        }
    }

    // MARK: - Signed URL refresh

    @MainActor
    func refreshAvatarURL(path: String, force: Bool) async {
        if !force, let item = avatarURLByPath[path] {
            let now = Date()
            if item.expiresAt.timeIntervalSince(now) > refreshLeeway {
                DLog.info("[ProfileStore] refreshAvatarURL skip (cached+valid) path=\(path)")
                return
            }
        }

        DLog.info("[ProfileStore] refreshAvatarURL start path=\(path) force=\(force)")

        do {
            let url = try await service.signedAvatarURL(for: path, expiresIn: Int(signedURLTTL))
            let expiresAt = Date().addingTimeInterval(signedURLTTL - refreshLeeway)
            avatarURLByPath[path] = SignedURLCacheItem(url: url, expiresAt: expiresAt)

            DLog.ok("[ProfileStore] refreshAvatarURL success path=\(path)")
        } catch {
            DLog.warn("[ProfileStore] refreshAvatarURL failed path=\(path) err=\(error)")
        }
    }

    // MARK: - Cache operations

    /// 版本化 path 后通常不需要清缓存，但保留以便你手动刷新调试用
    private func clearKingfisherCache(forPath path: String) {
        ImageCache.default.removeImage(forKey: path)
        // 如果你 Kingfisher 版本需要 async/throws，再按你实际 API 调整
    }

    // MARK: - Persistence helpers

    /// 启动先恢复本地快照，让 UI 立刻有内容（不代表服务器最新）
    @MainActor
    func restorePersistedMeIfPossible(for userId: UUID) {
        guard
            let data = UserDefaults.standard.data(forKey: persistedMeKey),
            let persisted = try? JSONDecoder().decode(PersistedMe.self, from: data),
            persisted.id == userId
        else {
            DLog.info("[ProfileStore] restorePersistedMeIfPossible miss uid=\(userId)")
            return
        }

        let restored = ProfileRow(
            id: persisted.id,
            username: persisted.username,
            fullName: persisted.fullName,
            avatarURL: persisted.avatarURL
        )

        me = restored
        profilesById[userId] = restored

        if let path = restored.avatarURL {
            // ✅ 已有可用 signedURL 就不打网络
            if signedURL(forPath: path) == nil {
                Task { await self.refreshAvatarURL(path: path, force: false) }
            }
        }

        DLog.ok("[ProfileStore] restored persisted me uid=\(userId) avatar=\(persisted.avatarURL ?? "nil")")
    }


    private func persistMe(_ profile: ProfileRow) {
        let payload = PersistedMe(
            id: profile.id,
            username: profile.username,
            fullName: profile.fullName,
            avatarURL: profile.avatarURL,
            savedAt: Date()
        )

        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: persistedMeKey)
            DLog.ok("[ProfileStore] persisted me uid=\(profile.id)")
        } else {
            DLog.warn("[ProfileStore] persistMe encode failed uid=\(profile.id)")
        }
    }

    // MARK: - Reset

    @MainActor
    func reset() {
        DLog.info("[ProfileStore] reset")
        me = nil
        profilesById.removeAll()
        avatarURLByPath.removeAll()
        error = nil
        isLoadingMe = false

        bootstrappedUserId = nil
        UserDefaults.standard.removeObject(forKey: persistedMeKey)
    }
    
    
    // MARK: - Update username

    @MainActor
    func updateMyUsername(userId: UUID, username: String) async {
        error = nil
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            self.error = "用户名不能为空"
            return
        }

        do {
            var p = (me ?? profilesById[userId]) ?? ProfileRow(
                id: userId,
                username: nil,
                fullName: nil,
                avatarURL: nil
            )

            // 只更新 username，其他字段保留
            p.username = trimmed

            try await service.upsertProfile(p)

            // 写回内存
            me = p
            profilesById[userId] = p

            // 持久化（如果你已经有 persistMe）
            // persistMe(p)

            DLog.ok("[ProfileStore] updateMyUsername success uid=\(userId) username=\(trimmed)")
        } catch {
            self.error = error.localizedDescription
            DLog.err("[ProfileStore] updateMyUsername failed uid=\(userId) err=\(error)")
        }
    }

}
