//
//  ProfileService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import Foundation
import Supabase

final class ProfileService {
    private let supabase = SupabaseClientProvider.shared.client
    let bucket = "avatars"

    /// ✅ 版本化存储路径： "<uid>/avatar_<unix>.jpg"
    /// - 目的：避免同名覆盖导致 CDN/客户端缓存返回旧图
    func avatarPath(for uid: UUID) -> String {
        let v = Int(Date().timeIntervalSince1970)
        return "\(uid.uuidString.lowercased())/avatar_\(v).jpg"
    }

    // MARK: - Fetch profile

    /// 拉取 profile
    /// - 只有「确实没行」才返回默认；其它错误一律 throw
    func fetchProfile(userId uid: UUID) async throws -> ProfileRow {
        DLog.info("[ProfileService] fetchProfile start uid=\(uid)")

        do {
            let row: ProfileRow =
                try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: uid)
                    .single()
                    .execute()
                    .value

            DLog.ok("[ProfileService] fetchProfile success uid=\(uid) avatar=\(row.avatarURL ?? "nil")")
            return row

        } catch {
            let msg = String(describing: error)

            if msg.contains("406") || msg.localizedCaseInsensitiveContains("no rows") {
                DLog.warn("[ProfileService] fetchProfile no rows uid=\(uid) -> return default shell")
                return ProfileRow(
                    id: uid,
                    username: "Player\(uid.uuidString.prefix(4))",
                    fullName: nil,
                    avatarURL: nil
                )
            }

            DLog.err("[ProfileService] fetchProfile failed uid=\(uid) err=\(error)")
            throw error
        }
    }

    // MARK: - Upsert profile

    func upsertProfile(_ profile: ProfileRow) async throws {
        DLog.info("[ProfileService] upsertProfile start id=\(profile.id) username=\(profile.username ?? "nil") avatar=\(profile.avatarURL ?? "nil")")

        do {
            try await supabase
                .from("profiles")
                .upsert(profile)
                .execute()

            DLog.ok("[ProfileService] upsertProfile success id=\(profile.id)")
        } catch {
            DLog.err("[ProfileService] upsertProfile failed id=\(profile.id) err=\(error)")
            throw error
        }
    }

    // MARK: - Upload avatar

    /// 上传头像（JPEG）到 Storage，返回 path（不是 URL）
    func uploadAvatarJPEG(userId uid: UUID, jpegData: Data) async throws -> String {
        let path = avatarPath(for: uid)

        DLog.info("[ProfileService] uploadAvatarJPEG start uid=\(uid) bucket=\(bucket) path=\(path) bytes=\(jpegData.count)")

        do {
            try await supabase.storage
                .from(bucket)
                .upload(
                    path,
                    data: jpegData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: false   // ✅ 版本化路径，不需要覆盖
                    )
                )

            DLog.ok("[ProfileService] uploadAvatarJPEG success path=\(path)")
            return path

        } catch {
            DLog.err("[ProfileService] uploadAvatarJPEG failed path=\(path) err=\(error)")
            throw error
        }
    }

    // MARK: - Signed URL

    func signedAvatarURL(for path: String, expiresIn seconds: Int = 60 * 10) async throws -> URL {
        DLog.info("[ProfileService] signedAvatarURL start path=\(path) exp=\(seconds)s")

        do {
            let url = try await supabase.storage
                .from(bucket)
                .createSignedURL(path: path, expiresIn: seconds)

            DLog.ok("[ProfileService] signedAvatarURL success path=\(path)")
            return url

        } catch {
            DLog.err("[ProfileService] signedAvatarURL failed path=\(path) err=\(error)")
            throw error
        }
    }
}


extension ProfileService {
    
    // 定义缓存项结构
    struct ProfileInfo {
        let name: String
        let avatarDownloadURL: URL?
        let avatarPath: String?
    }
    
    /// ✅ 终极方法：批量拉取资料 + 并发签名头像
    func fetchProfilesAndSignAvatars(ids: [UUID]) async -> [UUID: ProfileInfo] {
        guard !ids.isEmpty else { return [:] }
        
        // 1. 数据库查询 (WHERE id IN (...))
        guard let rows: [ProfileRow] = try? await supabase
            .from("profiles")
            .select()
            .in("id", value: ids)
            .execute()
            .value else { return [:] }
        
        // 2. 并发处理头像签名
        return await withTaskGroup(of: (UUID, ProfileInfo).self) { group in
            for row in rows {
                group.addTask {
                    let name = row.username ?? "神秘特工"
                    var downloadURL: URL? = nil
                    let storagePath = row.avatarURL // 数据库里存的是 path
                    
                    // 如果有头像路径，生成签名 URL
                    if let path = storagePath, !path.isEmpty {
                        // 签名有效期设长一点 (例如 1 小时)，反正 Kingfisher 有缓存
                        downloadURL = try? await self.signedAvatarURL(for: path, expiresIn: 3600)
                    }
                    
                    let info = ProfileInfo(
                        name: name,
                        avatarDownloadURL: downloadURL,
                        avatarPath: storagePath
                    )
                    return (row.id, info)
                }
            }
            
            // 3. 汇总结果
            var result: [UUID: ProfileInfo] = [:]
            for await (uid, info) in group {
                result[uid] = info
            }
            return result
        }
    }
}
