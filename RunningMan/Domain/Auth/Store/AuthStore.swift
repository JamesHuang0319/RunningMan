//
//  AuthStore.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()
    private let supabase = SupabaseClientProvider.shared.client

    // ✅ App 状态
    var isAuthenticated: Bool = false
    var userId: UUID? = nil
    var lastError: String? = nil

    // ✅ UI / Debug
    var isBootstrapping: Bool = true
    var lastAuthEvent: String = "-"
    var lastCallbackURL: String = "-"
    var lastSessionExpired: Bool? = nil




    private var listeningTask: Task<Void, Never>?

    init() {
        startListening()
        Task { await bootstrap() }
    }

    // 把所有“是否登录”的判定收口到这里
    private func apply(session: Session?) {
        if let session, !session.isExpired {
            isAuthenticated = true
            userId = session.user.id
            lastSessionExpired = false
        } else {
            isAuthenticated = false
            userId = nil
            lastSessionExpired = session?.isExpired
        }
    }

    // App 启动时：从本地恢复 session
    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            let session = try await supabase.auth.session
            apply(session: session)
        } catch {
            apply(session: nil)
        }
    }

    // 监听登录/退出/刷新 token
    func startListening() {
        guard listeningTask == nil else { return }

        listeningTask = Task {
            for await state in supabase.auth.authStateChanges {
                if [.initialSession, .signedIn, .signedOut, .tokenRefreshed].contains(state.event) {
                    lastAuthEvent = "\(state.event)"
                    apply(session: state.session)
                }
            }
        }
    }

    // 发送 magic link
    func signInWithMagicLink(email: String) async {
        do {
            lastError = nil
            try await supabase.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "runningman://login-callback")
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    // 收到 deep link 后换取 session
    func handleOpenURL(_ url: URL) async {
        lastCallbackURL = url.absoluteString
        do {
            lastError = nil
            _ = try await supabase.auth.session(from: url)
            let session = try await supabase.auth.session
            apply(session: session)
        } catch {
            lastError = error.localizedDescription
            // ⚠️ 不建议这里强行 apply(nil)，避免“已登录但因为重复处理链接导致 UI 被踢回登录”
            // apply(session: nil)
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        apply(session: nil)
        lastError = nil
        lastAuthEvent = "signedOut(manual)"
        lastCallbackURL = "-"
    }

    // 需要时手动刷新一次（例如你想做“启动后强制校验”）
    func refreshSession() async {
        await bootstrap()
    }
}
