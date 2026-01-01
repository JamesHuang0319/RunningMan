//
//  RunningManApp.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/7.
//

import SwiftUI

@main
struct RunningManApp: App {
    @State private var game = GameStore()
    @State private var auth = AuthStore.shared
    @State private var profileStore = ProfileStore()

    init() {
        DLog.enabled = true
        DLog.info("App launched")
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environment(game)
                .environment(auth)
                .environment(profileStore)
                .onOpenURL { url in
                    print("✅ onOpenURL:", url.absoluteString)
                    Task { await auth.handleOpenURL(url) }
                }
        }
    }
}



