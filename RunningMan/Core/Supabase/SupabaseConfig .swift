//
//  SupabaseConfig .swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//

//
//  集中管理 Supabase 配置（URL / Key / bucket / table 等）
//

import Foundation

enum SupabaseConfig {
    // ✅ 你的项目 URL
    static let url = URL(string: "https://ilmnvhyfykcjbrxdumpt.supabase.co")!

    // ⚠️ 注意：不要把 service_role 放客户端，只能用 anon/publishable key
    static let anonKey = "sb_publishable_6kdlqflVw6BLRO3f-rdq9Q_HTMsSRq_"

    // 你用到的 Storage bucket（统一写在这）
    enum Storage {
        static let avatarsBucket = "avatars"
    }

    // 你用到的表名也可以集中（可选，但推荐）
    enum Table {
        static let profiles = "profiles"
        static let rooms = "rooms"
        static let roomPlayers = "room_players"
        static let locations = "locations"
        static let roomEvents = "room_events"
    }
}
