//
//  AchievementStatusItem.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/3.
//


// 用于 Modal 列表显示的 UI 模型
struct AchievementStatusItem: Identifiable {
    var id: String { definition.type }
    let definition: AchievementDefinition
    let userRecord: UserAchievementRow? // 如果为 nil，说明未解锁
    
    var isUnlocked: Bool { userRecord != nil }
    var isVisibleInHome: Bool {
        guard let r = userRecord else { return false }
        return !r.isHidden
    }
}
