//
//  FruitSkill.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/28.
//

import SwiftUI

struct FruitSkill: Identifiable, Hashable {
    let id: UUID = UUID()
    let icon: String
    let name: String
    let description: String
    let usageMessage: String // 释放技能后的提示语
    let color: Color
    let cooldown: TimeInterval
    
    static let allSkills: [FruitSkill] = [
        FruitSkill(icon: "🥭", name: "芒果隐身", description: "在敌人地图上消失 30 秒", usageMessage: "你已进入隐身状态，持续30秒", color: .orange, cooldown: 60),
        FruitSkill(icon: "🍌", name: "香蕉陷阱", description: "放置陷阱，踩中者定身 5 秒", usageMessage: "陷阱已放置在当前位置", color: .yellow, cooldown: 45),
        FruitSkill(icon: "🍉", name: "西瓜轰炸", description: "使范围内敌人屏幕模糊", usageMessage: "西瓜炸弹已投向最近的敌人", color: .red, cooldown: 50),
        FruitSkill(icon: "🍇", name: "葡萄雷达", description: "扫描 500m 内隐身单位", usageMessage: "雷达扫描中... 未发现隐藏目标", color: .purple, cooldown: 30)
    ]
}
