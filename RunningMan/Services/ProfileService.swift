//
//  ProfileService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import Foundation
import Supabase

final class ProfileService {
    private let supabase = SupabaseService.shared.client
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
