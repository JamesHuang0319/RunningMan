import SwiftUI

struct DebugOverlay: View {
    @Environment(GameStore.self) private var game
    @State private var expanded: Bool = false
    @State private var showExplain: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded ? "ladybug.fill" : "ladybug")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if expanded {
                    Button {
                        showExplain = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("States: \(game.statesByUserId.count)")
                    Text("States(coord): \(game.statesByUserId.values.filter { $0.coordinate != nil }.count)")
                    Text("Presence: \(game.presenceOnlineIds.count)")
                    Text("Players(map): \(game.mapPlayers.count)")
                    Text("Players(lobby): \(game.lobbyPlayers.count)")
                }
                .font(.caption2.monospaced())
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: showExplain) { _, v in
            guard v else { return }
            // 这里你可以改成用你现成的 TacticalAlertView/triggerInstruction
            // 如果你想“像技能说明一样弹”，建议让 MainMapView 提供一个 closure 来触发提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showExplain = false
            }
        }
    }
}
