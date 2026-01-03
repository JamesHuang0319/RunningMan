//
//  AuthGateView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import SwiftUI

struct AuthGateView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(GameStore.self) private var game

    var body: some View {
        Group {
            if auth.isBootstrapping {
                ProgressView("正在恢复登录…")
            } else if auth.isAuthenticated {
                RootView()
                .task {
                    game.meId = auth.userId
                    DLog.ok(
                        "AuthGate injected game.meId=\(auth.userId?.uuidString ?? "-")"
                    )
                }
            } else {
                AuthView()
            }
        }
    }
}
