//
//  AllAchievementsView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2026/1/3.
//

// Views/Profile/AllAchievementsView.swift

import SwiftUI

struct AllAchievementsView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    
    // 计算属性：将列表拆分为两组
    var groupedAchievements: (unlocked: [AchievementStatusItem], locked: [AchievementStatusItem]) {
        let all = store.allAchievementsStatus
        return (
            unlocked: all.filter { $0.isUnlocked },
            locked: all.filter { !$0.isUnlocked }
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                // ✅ 第一组：已解锁
                if !groupedAchievements.unlocked.isEmpty {
                    Section {
                        ForEach(groupedAchievements.unlocked) { status in
                            AchievementRow(status: status, store: store)
                        }
                    } header: {
                        Text("已解锁 (\(groupedAchievements.unlocked.count))")
                    }
                }
                
                // ✅ 第二组：未解锁
                if !groupedAchievements.locked.isEmpty {
                    Section {
                        ForEach(groupedAchievements.locked) { status in
                            AchievementRow(status: status, store: store)
                        }
                    } header: {
                        Text("未解锁")
                    }
                }
            }
            .navigationTitle("所有荣誉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// 抽离出的 Row 组件，保持代码整洁
struct AchievementRow: View {
    let status: AchievementStatusItem
    let store: ProfileStore
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(status.isUnlocked
                          ? Color(hex: status.definition.colorHex).opacity(0.15)
                          : Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: status.definition.iconName)
                    .font(.title3)
                    .foregroundStyle(status.isUnlocked
                                     ? Color(hex: status.definition.colorHex).gradient
                                     : Color.gray.gradient)
                    .grayscale(status.isUnlocked ? 0 : 1.0)
            }
            
            // 文本
            VStack(alignment: .leading, spacing: 4) {
                Text(status.definition.name)
                    .font(.body.bold())
                    .foregroundStyle(status.isUnlocked ? .primary : .secondary)
                
                if let desc = status.definition.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // 操作区
            if let record = status.userRecord {
                // 如果是已解锁的
                if record.isHidden {
                    // 如果被隐藏了，显示“展示”按钮
                    Button("展示") {
                        Task { await store.toggleAchievementVisibility(dbID: record.id, hide: false) }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(.blue)
                } else {
                    // 正常状态
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            } else {
                // 未解锁
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.3))
            }
        }
        .padding(.vertical, 4)
        // 未解锁的稍微调低透明度
        .opacity(status.isUnlocked ? 1.0 : 0.6)
    }
}
