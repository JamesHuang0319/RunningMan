//
//  SetupSheet.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/15.
//

import SwiftUI

struct SetupSheet: View {
    @Environment(GameManager.self) var game
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Capsule()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.headline)
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text("游戏设置").font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("游戏区域").font(.subheadline.weight(.semibold))
                        Picker("选择区域", selection: Bindable(game).selectedRegion) {
                            ForEach(GameRegion.allRegions) { r in
                                Text(r.name).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider().opacity(0.4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("我的角色").font(.subheadline.weight(.semibold))
                        Picker("我的角色", selection: Bindable(game).currentUser.role) {
                            ForEach(GameRole.allCases, id: \.self) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(height: 44)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HStack {
                    Text(game.selectedRegion.name)
                        .font(.headline)
                    Spacer()
                    Text(game.currentUser.role.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }

            Button { game.startGame() } label: {
                Label("开始游戏", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text("开始后可随时切到「我」查看荣誉与设置。")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(radius: 12, y: 6)
    }
}

#Preview("SetupSheet") {
    let game = GameManager()
    return ZStack {
        Color.gray.opacity(0.15).ignoresSafeArea()
        SetupSheet(isExpanded: .constant(true)).environment(game)
            .padding()
    }
}
