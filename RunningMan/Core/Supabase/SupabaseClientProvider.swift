//
//  SupabaseClientProvider.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//
//
//  负责创建并持有 SupabaseClient（你原 SupabaseService 的职责）
//

import Foundation
import Supabase

final class SupabaseClientProvider {

    // ✅ 先保留 shared，避免你全项目大改
    //    等你重构成熟，再把 shared 拿掉（由 App 注入）
    static let shared = SupabaseClientProvider()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        print("✅ SupabaseClientProvider init")
    }
}
