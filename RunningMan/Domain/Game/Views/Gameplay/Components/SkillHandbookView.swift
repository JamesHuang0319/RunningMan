//
//  SkillHandbookView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/28.
//
import SwiftUI

// MARK: - 4. 说明书组件 (可读性增强版)
struct SkillHandbookView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("战术指南")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Spacer()
            }
            .foregroundStyle(.blue.opacity(0.95))

            // List
            VStack(spacing: 12) {
                ForEach(FruitSkill.allSkills) { skill in
                    HStack(alignment: .center, spacing: 12) {

                        // Icon pill (略收一点，让文本区更宽)
                        Text(skill.icon)
                            .font(.system(size: 20))
                            .frame(width: 34, height: 34)
                            .background(skill.color.opacity(0.14), in: Circle())
                            .overlay(
                                Circle().stroke(skill.color.opacity(0.22), lineWidth: 1)
                            )

                        // Text
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(skill.description)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer(minLength: 0)
                    }
                    // 增加一点“行的可点击/可呼吸”区域（看起来更高级）
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .frame(width: 288) // ✅ 宽一点 = 字体能变大还保持一行
    }
}
