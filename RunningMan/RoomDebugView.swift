import SwiftUI

#if DEBUG
struct RoomDebugView: View {
    @Environment(GameStore.self) private var game
    @Environment(AuthStore.self) private var auth

    // 你把 dashboard 创建出来的 roomId 写在这里
    private let roomId = UUID(uuidString: "40d4121e-cee6-479a-96e6-a1c882ce0cbf")!

    var body: some View {
        List {
            Section("Auth") {
                Text("meId: \(auth.userId?.uuidString ?? "-")")
            }

            Section("Room") {
                Text("roomId: \(roomId.uuidString)")
                Text("subscribed: \(game.roomId?.uuidString ?? "-")")
                Text("players cached: \(game.statesByUserId.count)")
            }

            Section("Actions") {
                Button("🚀 Join P0 Room") {
                    Task { await game.joinRoom(roomId: roomId) }
                }

                Button("👋 Leave") {
                    Task { await game.leaveRoom() }
                }
            }
        }
        .navigationTitle("P0 Room Debug")
    }
}
#endif
