//
//  AuthGateView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import SwiftUI

struct AuthGateView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            if auth.isBootstrapping {
                ProgressView("正在恢复登录…")
            } else if auth.isAuthenticated {
                RootView()
            } else {
                AuthView()
            }
        }
    }
}

