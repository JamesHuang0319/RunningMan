import SwiftUI
import Kingfisher

struct PlayerAnnotationView: View {
    let player: PlayerDisplay
    let distance: Double

    @State private var pulse = false
    @State private var dangerPulse = false

    // MARK: - Cloak/Reveal (你把这两段接到自己的 state 读取上即可)
    private var now: Date { Date() }

    private var cloakUntil: Date? {
        player.stateDate("cloak_until")
    }
    private var revealUntil: Date? {
        player.stateDate("reveal_until")
    }

    /// ✅ “正在隐身”（时间未到）
    private var isCloakedNow: Bool {
        guard let t = cloakUntil else { return false }
        return now < t
    }

    /// ✅ “被揭露中”（时间未到）
    private var isRevealedNow: Bool {
        guard let t = revealUntil else { return false }
        return now < t
    }

    var body: some View {
        VStack(spacing: 5) {

            ZStack {
                // 1) 暴露态：呼吸外环
                if player.isExposed {
                    ExposedBreathingRing()
                        .frame(width: 78, height: 78)
                        .opacity(player.isOffline ? 0.25 : 1.0)
                        .transition(.opacity)
                        .zIndex(0)
                }

                // 2) 近距离威胁：红色警戒环（<20m）
                if !player.isMe && distance < 20 {
                    Circle()
                        .stroke(Color.red.opacity(0.55), lineWidth: 4)
                        .frame(width: 62, height: 62)
                        .scaleEffect(dangerPulse ? 1.35 : 1.0)
                        .opacity(dangerPulse ? 0.0 : 1.0)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                                dangerPulse = true
                            }
                        }
                        .zIndex(1)
                }

                // 3) ✅ 被雷达揭露：给一个“扫描环”提示（很轻，不吵）
                if isRevealedNow && !player.isMe {
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 2)
                        .frame(width: 62, height: 62)
                        .scaleEffect(pulse ? 1.25 : 0.95)
                        .opacity(pulse ? 0.0 : 0.9)
                        .onAppear {
                            withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                                pulse = true
                            }
                        }
                        .zIndex(1)
                }

                // 4) 头像主体
                avatarCore
                    .zIndex(2)

                // 5) ✅ 自己隐身：给自己一个小芒果/隐身角标（只有自己看得到）
                if player.isMe && isCloakedNow {
                    Text("🥭")
                        .font(.system(size: 16))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .offset(x: 18, y: -18)
                        .zIndex(3)
                }

                // ❌ caught 角标删除：地图不画 caught 的人，数据层负责过滤
            }
            .frame(width: 54, height: 54)
            .opacity(player.isOffline ? 0.35 : 1.0)

            // 标签（名字/距离）
            tagView
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: player.coordinate)
    }

    // MARK: - Avatar Core

    private var avatarCore: some View {
        ZStack {
            Circle()
                .fill(roleColor)
                .frame(width: 46, height: 46)
                .shadow(color: roleColor.opacity(0.45), radius: 8, y: 4)

            if let url = player.avatarDownloadURL, let cacheKey = player.avatarCacheKey {
                KFImage(source: .network(Kingfisher.ImageResource(downloadURL: url, cacheKey: cacheKey)))
                    .placeholder { ProgressView().tint(.white) }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    // ✅ 自己隐身：头像轻微变淡（只有自己）
                    .opacity(player.isMe && isCloakedNow ? 0.6 : 1.0)
            } else {
                Image(systemName: roleIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(player.isMe && isCloakedNow ? 0.6 : 1.0)
            }
        }
        .scaleEffect(player.isMe ? 1.08 : 1.0)
    }

    // MARK: - Tag

    private var tagView: some View {
        let showDistance = !player.isMe && distance < 18
        let text = showDistance ? "\(Int(distance))m" : player.displayName

        return HStack(spacing: 6) {
            if player.isExposed {
                Text("暴露")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.95), in: Capsule())
            }

            // ✅ 被揭露：加个小“👁”提示（猎人能理解：这是雷达显形）
            if isRevealedNow && !player.isMe {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(text)
                .font(.system(size: 10.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: 110)
        .foregroundStyle(.white)
        .background(roleColor.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }

    // MARK: - Exposed Ring

    private func ExposedBreathingRing() -> some View {
        ZStack {
            Circle()
                .stroke(Color.yellow.opacity(0.85), lineWidth: 5)
                .blur(radius: 0.2)
                .scaleEffect(pulse ? 1.15 : 0.98)
                .opacity(pulse ? 0.15 : 0.55)

            Circle()
                .stroke(Color.orange.opacity(0.75), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                .scaleEffect(pulse ? 1.05 : 0.95)
                .opacity(pulse ? 0.85 : 0.45)
        }
    }

    // MARK: - Helpers

    private var roleColor: Color {
        switch player.role {
        case .runner: return .blue
        case .hunter: return .red
        case .spectator: return .purple
        }
    }

    private var roleIcon: String {
        switch player.role {
        case .runner: return "figure.run"
        case .hunter: return "eye.fill"
        case .spectator: return "camera.fill"
        }
    }
}

// MARK: - 你需要在 PlayerDisplay 上补一个轻量 helper（按你实际 state 类型改）
private extension PlayerDisplay {
    func stateDate(_ key: String) -> Date? {
        // 你自己接：从 state jsonb 里把 key 解析成 Date
        // e.g. ISO8601 / timestamptz string -> Date
        return nil
    }
}
