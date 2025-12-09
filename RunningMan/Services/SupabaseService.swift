//
//  SupabaseService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(
                string: "https://ilmnvhyfykcjbrxdumpt.supabase.co"
            )!,
            supabaseKey: "sb_publishable_6kdlqflVw6BLRO3f-rdq9Q_HTMsSRq_",
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
