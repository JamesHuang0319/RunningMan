//
//  RootView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

import SwiftUI

enum AppTab: Hashable {
    case game
    case profile
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ProfileStore.self) private var profileStore

    @State private var tab: AppTab = .game

    var body: some View {
        TabView(selection: $tab) {
            GameFlowView()
                .tabItem { Label("游戏", systemImage: "map") }
                .tag(AppTab.game)

            ProfileView()
                .tabItem { Label("我", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        // ✅ 登录后启动初始化：先 restore 本地快照，后台刷新云端
        .task(id: auth.userId) {
            if let uid = auth.userId {
                await profileStore.bootstrapIfNeeded(userId: uid)
            } else {
                await MainActor.run { profileStore.reset() }
            }
        }
    }
}
