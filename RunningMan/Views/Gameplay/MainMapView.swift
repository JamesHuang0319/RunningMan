//
//  MainMapView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/14.
//

// Views/Gameplay/MainMapView.swift
import MapKit
import Observation
import SwiftUI

struct MainMapView: View {
    @Environment(GameManager.self) var game

    @State private var position: MapCameraPosition
    @State private var isFollowingUser: Bool = false

    init() {
        _position = State(initialValue: .automatic)
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            ForEach(game.otherPlayers) { player in
                Annotation(player.name, coordinate: player.coordinate) {
                    PlayerAnnotationView(player: player)
                        .onTapGesture {
                            Task { await game.navigate(to: player) }
                        }
                }
            }

            if let zone = game.safeZone {
                MapCircle(center: zone.center, radius: zone.radius)
                    .foregroundStyle(.blue.opacity(0.1))
                    .stroke(.blue, lineWidth: 2)
            }

            if let route = game.currentRoute {
                MapPolyline(route).stroke(.orange, lineWidth: 5)
            }
        }
        .mapControls {
            MapScaleView()
            MapCompass()
            MapPitchToggle()
        }
        .onAppear { setupInitialCamera() }
        .onChange(of: game.locationService.currentLocation) { _, newLoc in
            handleLocationUpdate(newLoc)
        }
        .onMapCameraChange(frequency: .onEnd) {
            isFollowingUser = false
        }
        .mapStyle(.standard(elevation: .realistic))

        // 顶部 HUD：自动避开状态栏/刘海
        .safeAreaInset(edge: .top, spacing: 0) {
            GameHUDView()
                .padding(.horizontal, 14)
                .padding(.top, 10)
        }

        //  底部 Controls：自动避开 Home Indicator
        .safeAreaInset(edge: .bottom) {
            GameplayControlsView(
                 isFollowingUser: $isFollowingUser,
                 onToggleCamera: updateCameraMode
             )
        }

    }

    // MARK: - Helper Methods (将逻辑代码抽取成函数，进一步增加可读性)

    private func setupInitialCamera() {
        withAnimation {
            position = .region(
                MKCoordinateRegion(
                    center: game.selectedRegion.center,
                    latitudinalMeters: game.selectedRegion.initialRadius * 2.5,
                    longitudinalMeters: game.selectedRegion.initialRadius * 2.5
                )
            )
        }
    }

    private func handleLocationUpdate(_ newLoc: CLLocationCoordinate2D?) {
        if let coord = newLoc {
            game.currentUser.coordinate = coord
            if isFollowingUser {
                withAnimation {
                    position = .userLocation(fallback: .automatic)
                }
            }
        }
    }

    private func updateCameraMode() {
        if isFollowingUser {
            withAnimation {
                position = .userLocation(
                    followsHeading: true,
                    fallback: .automatic
                )
            }
        } else {
            withAnimation {
                position = .region(
                    MKCoordinateRegion(
                        center: game.selectedRegion.center,
                        latitudinalMeters: game.selectedRegion.initialRadius
                            * 2.5,
                        longitudinalMeters: game.selectedRegion.initialRadius
                            * 2.5
                    )
                )
            }
        }
    }
}

#Preview {
    // 1. 创建一个用于预览的 GameManager 实例
    // 这个实例只在 Preview 中存在，不会影响真实 App
    let mockGame = GameManager()

    // 2. 配置这个实例，模拟一个真实的游戏场景

    // a. 强制进入游戏状态，否则 RootView 会显示 SetupView
    mockGame.phase = .playing

    // b. 设置一个模拟的安全区（毒圈）
    mockGame.safeZone = SafeZone(
        center: GameRegion.csuNewCampus.center,  // 以中南大学为中心
        radius: 800  // 半径800米
    )

    // c. 添加几个模拟的其他玩家，用于在地图上显示图标
    mockGame.otherPlayers = [
        Player(
            id: UUID(),
            name: "🏃 小明",
            role: .runner,
            status: .active,
            // 稍微偏离中心一点，方便观察
            coordinate: CLLocationCoordinate2D(
                latitude: 28.1670,
                longitude: 112.9380
            )
        ),
        Player(
            id: UUID(),
            name: "👻 小红",
            role: .hunter,
            status: .active,
            coordinate: CLLocationCoordinate2D(
                latitude: 28.1650,
                longitude: 112.9350
            )
        ),
    ]

    // d. (可选) 模拟一条正在导航的路线，测试导航线显示
    // 注意: MKRoute 构造起来比较复杂，通常在 Preview 中省略这一步，
    // 或者只在专门测试导航UI时构造。这里我们先不加。
    // mockGame.currentRoute = ...

    // 3. 返回你的 MainMapView
    return MainMapView()
        // 4. (关键) 将配置好的 mockGame 注入到环境中
        // 这样 MainMapView 才能读取到我们上面设置的假数据
        .environment(mockGame)
}
