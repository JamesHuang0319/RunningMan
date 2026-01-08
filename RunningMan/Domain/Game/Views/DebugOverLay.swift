import SwiftUI

struct DebugOverlay: View {
    @Environment(GameStore.self) private var game
    @State private var expanded: Bool = false
    @State private var showExplain: Bool = false
    // ✅ 从 MainMapView 传进来
    @Binding var debugDistanceOverride: Double?

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
                let readyCount = game.statesByUserId.values.filter { $0.status == .ready }.count
                let activeCount = game.statesByUserId.values.filter { $0.status == .active }.count
                let finishedCount = game.statesByUserId.values.filter { $0.status == .finished }.count

                VStack(alignment: .leading, spacing: 4) {
                    Text("Phase: \(String(describing: game.phase))")
                    Text("RoomStatus: \(game.room?.status.rawValue ?? "-")")
                    Text("isInRoom: \(game.isInRoom ? "true" : "false")")

                    Text("States: \(game.statesByUserId.count)")
                    Text("Ready: \(readyCount)  Active: \(activeCount)  Finished: \(finishedCount)")

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
        #if DEBUG
       .overlay(alignment: .bottomLeading) {
           VStack(spacing: 8) {
               Button("Dist=9.5m") { debugDistanceOverride = 9.5 }
               Button("Dist=12m")  { debugDistanceOverride = 12 }
               Button("Dist=nil")  { debugDistanceOverride = nil }
           }
           .padding(12)
           .background(.ultraThinMaterial)
           .clipShape(RoundedRectangle(cornerRadius: 12))
           .padding(.leading, 12)
           .padding(.bottom, 120)
       }
       #endif
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
