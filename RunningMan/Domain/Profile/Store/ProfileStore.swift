//
//  ProfileStore.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/24.
//

import Foundation
import Kingfisher
import Observation
import SwiftUI

@Observable
final class ProfileStore {

    // MARK: - Dependencies
    
    private let service: ProfileService

    // MARK: - Init
    
    private var bootstrappedUserId: UUID?

    init(service: ProfileService = ProfileService()) {
        self.service = service
        DLog.info("[ProfileStore] init")
    }

    // MARK: - State (UI State)

    /// 当前登录用户的完整 Profile (包含统计数据)
    var me: ProfileRow?

    /// 全局加载状态 (适用于页面骨架屏)
    var isLoadingMe: Bool = false

    /// 全局错误信息 (用于 Toast 或 Alert 展示)
    var error: String?

    /// 多用户缓存池:用于好友列表、地图头像等场景
    /// Key: UserID, Value: ProfileRow
    var profilesById: [UUID: ProfileRow] = [:]

    /// 成就列表数据源 (UI 直接遍历此数组渲染)
    var achievements: [AchievementItem] = []

    /// 成就配置字典 (内存缓存)
    /// Key: type (e.g. "first_win"), Value: Definition (图标、颜色、名称)
    /// 启动时从数据库拉取，用于动态渲染成就 UI
    var achievementDefs: [String: AchievementDefinition] = [:]

    // MARK: - Cache (Avatar Signed URL)

    /// Signed URL 缓存项
    struct SignedURLCacheItem {
        let url: URL
        let expiresAt: Date
    }

    /// 头像 Signed URL 缓存池
    /// Key: Storage Path (e.g. "uid/avatar_123.jpg")
    private(set) var avatarURLByPath: [String: SignedURLCacheItem] = [:]

    /// Signed URL 有效期 (10分钟)
    private let signedURLTTL: TimeInterval = 60 * 10

    /// 刷新缓冲时间 (1分钟)：如果剩余有效期少于此值，提前刷新
    private let refreshLeeway: TimeInterval = 60

    // MARK: - Persistence Keys & Models

    private let persistedMeKey = "profile.persisted.me.v2"
    private let persistedAchievementsKey = "profile.persisted.achievements.v1"
    private let persistedDefsKey = "profile.persisted.defs.v1"

    /// 本地持久化模型：Me 的快照 (包含统计数据)
    private struct PersistedMe: Codable {
        let id: UUID
        let username: String?
        let fullName: String?
        let avatarURL: String?
        let totalGames: Int?
        let totalWins: Int?
        let totalDistance: Double?
        let savedAt: Date
    }

    /// 本地持久化模型：成就快照 (只存关键 ID)
    private struct PersistedAchievement: Codable {
        let dbID: Int?
        let type: String
    }

    // MARK: - Bootstrap (App Entry Point)

    /// ✅ 启动引导：登录后在 RootView 调用
    /// 1. 优先恢复本地缓存 (秒开 UI)
    /// 2. 后台静默刷新云端数据
    @MainActor
    func bootstrapIfNeeded(userId: UUID) async {
        guard bootstrappedUserId != userId else { return }
        bootstrappedUserId = userId

        // 1. 恢复静态配置 (必须最先恢复，否则成就无法渲染)
        restoreDefinitions()

        // 2. 恢复用户数据 (Profile + Achievements)
        restorePersistedMeIfPossible(for: userId)
        restorePersistedAchievements()

        // 3. 并发拉取最新配置和数据
        await loadAchievementDefinitions()  // 先拉配置
        await loadMe(userId: userId, usePersistedFirst: false)  // 再拉个人数据
    }

    // MARK: - Core Logic: Load User Profile

    /// 拉取当前用户 Profile (包含统计数据) 并处理头像
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

        // 尝试从缓存恢复 (UI 优化)
        if usePersistedFirst, me?.id != userId {
            restorePersistedMeIfPossible(for: userId)
            restorePersistedAchievements()
        }

        DLog.info("[ProfileStore] loadMe start uid=\(userId)")

        do {
            let oldPath = profilesById[userId]?.avatarURL

            // 1. 网络请求 Profile
            let p = try await service.fetchProfile(userId: userId)
            me = p
            profilesById[userId] = p
            
            // 2. 更新本地缓存
            persistMe(p)

            // 3. 处理头像 Signed URL
            if let newPath = p.avatarURL {
                let pathChanged = (oldPath != newPath)

                if forceRefreshAvatar || pathChanged, clearImageCacheIfForce {
                    clearKingfisherCache(forPath: newPath)
                }

                await refreshAvatarURL(
                    path: newPath,
                    force: forceRefreshAvatar || pathChanged
                )
            }

            // 4. 并行加载成就列表
            await loadAchievements(userId: userId)

            DLog.ok("[ProfileStore] loadMe success")
        } catch {
            self.error = error.localizedDescription
            DLog.err("[ProfileStore] loadMe failed: \(error)")
        }
    }

    // MARK: - Core Logic: Achievements

    /// 加载成就配置字典 (Definitions)
    func loadAchievementDefinitions() async {
        do {
            // 调用 Service 获取配置
            let defs = try await service.fetchAchievementDefinitions()

            // 更新内存字典
            self.achievementDefs = Dictionary(
                uniqueKeysWithValues: defs.map { ($0.type, $0) }
            )

            // 更新本地缓存
            persistDefinitions()

            DLog.ok("[ProfileStore] Loaded \(achievementDefs.count) definitions")
        } catch {
            DLog.err("[ProfileStore] Failed to load definitions: \(error)")
        }
    }
    
    /// 加载用户获得的成就
    @MainActor
    func loadAchievements(userId: UUID) async {
        do {
            let rows = try await service.fetchAchievements(userId: userId)
            // 转换：DB Model -> UI Model (依赖 achievementDefs)
            self.achievements = rows.compactMap { mapToUIModel(row: $0) }
            // 缓存：存入 UserDefaults
            persistAchievements(self.achievements)
        } catch {
            DLog.err("Load achievements failed: \(error)")
        }
    }

    /// 删除某个成就 (UI 操作)
    @MainActor
    func removeAchievement(item: AchievementItem) async {
        // 1. 乐观更新 UI (带动画)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let index = achievements.firstIndex(of: item) {
                achievements.remove(at: index)
            }
        }

        // 2. 更新本地缓存
        persistAchievements(achievements)

        // 3. 发送网络请求
        if let dbID = item.dbID {
            do {
                try await service.deleteAchievement(id: dbID)
            } catch {
                DLog.err("Failed to delete achievement: \(error)")
                // TODO: 生产环境可考虑回滚 UI 或弹 Toast
            }
        }
    }

    // MARK: - Core Logic: Updates

    /// 更新头像 (上传 -> 更新 DB -> 刷新 URL)
    @MainActor
    func updateMyAvatar(userId: UUID, jpegData: Data) async {
        error = nil
        DLog.info("[ProfileStore] updateMyAvatar bytes=\(jpegData.count)")

        do {
            // 1. 上传 Storage
            let path = try await service.uploadAvatarJPEG(
                userId: userId,
                jpegData: jpegData
            )

            // 2. 更新 DB
            var p = (me ?? profilesById[userId]) ?? ProfileRow(
                id: userId,
                username: nil,
                fullName: nil,
                avatarURL: nil
            )
            p.avatarURL = path
            try await service.upsertProfile(p)

            // 3. 更新内存 & 缓存
            me = p
            profilesById[userId] = p
            persistMe(p)

            // 4. 强制刷新 Signed URL
            await refreshAvatarURL(path: path, force: true)

            DLog.ok("[ProfileStore] updateMyAvatar success")
        } catch {
            self.error = error.localizedDescription
            DLog.err("[ProfileStore] updateMyAvatar failed: \(error)")
        }
    }

    /// 更新用户名
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
            p.username = trimmed

            // 1. 更新 DB
            try await service.upsertProfile(p)

            // 2. 更新内存 & 缓存
            me = p
            profilesById[userId] = p
            persistMe(p)

            DLog.ok("[ProfileStore] updateMyUsername success")
        } catch {
            self.error = error.localizedDescription
            DLog.err("[ProfileStore] updateMyUsername failed: \(error)")
        }
    }
    
    // MARK: - Core Logic: Batch Load

    /// 批量加载用户 Profile (用于地图/好友列表)
    /// 包含自动去重和 Signed URL 刷新
    func loadProfiles(userIds: [UUID]) async {
        DLog.info("[ProfileStore] loadProfiles start count=\(userIds.count)")

        for uid in userIds {
            // 内存缓存命中则跳过
            if profilesById[uid] != nil { continue }

            do {
                let p = try await service.fetchProfile(userId: uid)
                profilesById[uid] = p

                if let path = p.avatarURL {
                    await refreshAvatarURL(path: path, force: false)
                }
            } catch {
                DLog.warn("[ProfileStore] loadProfiles failed uid=\(uid) err=\(error)")
            }
        }
    }

    // MARK: - UI Helpers

    /// 通过 path 获取可用 Signed URL (View 使用)
    func signedURL(forPath path: String) -> URL? {
        guard let item = avatarURLByPath[path] else { return nil }
        if item.expiresAt <= Date() { return nil }
        return item.url
    }

    func avatarPath(for profile: ProfileRow) -> String? { profile.avatarURL }
    func avatarPath(for uid: UUID) -> String? { profilesById[uid]?.avatarURL }

    var winRateString: String {
        guard let games = me?.totalGames, let wins = me?.totalWins, games > 0 else {
            return "--"
        }
        let rate = (Double(wins) / Double(games)) * 100
        return String(format: "%.0f", rate)
    }

    var totalDistanceString: String {
        String(format: "%.1f", me?.totalDistance ?? 0.0)
    }

    var totalGamesString: String {
        "\(me?.totalGames ?? 0)"
    }

    // MARK: - Persistence Implementation

    private func persistMe(_ profile: ProfileRow) {
        let payload = PersistedMe(
            id: profile.id,
            username: profile.username,
            fullName: profile.fullName,
            avatarURL: profile.avatarURL,
            totalGames: profile.totalGames,
            totalWins: profile.totalWins,
            totalDistance: profile.totalDistance,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: persistedMeKey)
        }
    }

    private func persistAchievements(_ items: [AchievementItem]) {
        let persistedItems = items.compactMap { item -> PersistedAchievement? in
            return PersistedAchievement(
                dbID: item.dbID,
                type: item.type
            )
        }
        if let data = try? JSONEncoder().encode(persistedItems) {
            UserDefaults.standard.set(data, forKey: persistedAchievementsKey)
        }
    }
    
    private func persistDefinitions() {
        let list = Array(achievementDefs.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: persistedDefsKey)
        }
    }

    @MainActor
    private func restorePersistedMeIfPossible(for userId: UUID) {
        guard
            let data = UserDefaults.standard.data(forKey: persistedMeKey),
            let p = try? JSONDecoder().decode(PersistedMe.self, from: data),
            p.id == userId
        else { return }

        // 恢复 Me
        let restored = ProfileRow(
            id: p.id,
            username: p.username,
            fullName: p.fullName,
            avatarURL: p.avatarURL,
            totalGames: p.totalGames,
            totalWins: p.totalWins,
            totalDistance: p.totalDistance
        )
        me = restored
        profilesById[userId] = restored

        // 尝试刷新头像
        if let path = restored.avatarURL, signedURL(forPath: path) == nil {
            Task { await self.refreshAvatarURL(path: path, force: false) }
        }
        DLog.ok("[ProfileStore] restored persisted me")
    }

    @MainActor
    private func restorePersistedAchievements() {
        guard
            let data = UserDefaults.standard.data(forKey: persistedAchievementsKey),
            let pItems = try? JSONDecoder().decode([PersistedAchievement].self, from: data)
        else { return }

        // 依赖于 achievementDefs 是否已恢复
        self.achievements = pItems.compactMap { p in
            return createAchievementItem(dbID: p.dbID, type: p.type)
        }
        DLog.ok("[ProfileStore] restored \(self.achievements.count) achievements")
    }
    
    private func restoreDefinitions() {
        if let data = UserDefaults.standard.data(forKey: persistedDefsKey),
            let list = try? JSONDecoder().decode([AchievementDefinition].self, from: data) {
            self.achievementDefs = Dictionary(uniqueKeysWithValues: list.map { ($0.type, $0) })
            DLog.ok("[ProfileStore] restored definitions")
        }
    }

    // MARK: - Internal Helpers

    /// 生成 UI 用的 AchievementItem
    private func mapToUIModel(row: UserAchievementRow) -> AchievementItem? {
        return createAchievementItem(dbID: row.id, type: row.type)
    }

    /// 查字典 (Defs) 生成 Item
    private func createAchievementItem(dbID: Int?, type: String) -> AchievementItem? {
        guard let def = achievementDefs[type] else { return nil }
        return AchievementItem(
            dbID: dbID,
            type: type,
            color: Color(hex: def.colorHex),
            icon: def.iconName,
            name: def.name
        )
    }

    @MainActor
    private func refreshAvatarURL(path: String, force: Bool) async {
        if !force, let item = avatarURLByPath[path] {
            let now = Date()
            if item.expiresAt.timeIntervalSince(now) > refreshLeeway { return }
        }

        do {
            let url = try await service.signedAvatarURL(
                for: path,
                expiresIn: Int(signedURLTTL)
            )
            let expiresAt = Date().addingTimeInterval(signedURLTTL - refreshLeeway)
            avatarURLByPath[path] = SignedURLCacheItem(url: url, expiresAt: expiresAt)
        } catch {
            DLog.warn("[ProfileStore] refreshAvatarURL failed: \(error)")
        }
    }

    private func clearKingfisherCache(forPath path: String) {
        ImageCache.default.removeImage(forKey: path)
    }

    // MARK: - Reset (Log Out)

    @MainActor
    func reset() {
        DLog.info("[ProfileStore] reset")
        me = nil
        profilesById.removeAll()
        avatarURLByPath.removeAll()
        achievements.removeAll()
        error = nil
        isLoadingMe = false
        bootstrappedUserId = nil

        UserDefaults.standard.removeObject(forKey: persistedMeKey)
        UserDefaults.standard.removeObject(forKey: persistedAchievementsKey)
        // Defs 不删，因为是通用配置
    }
}
