import SwiftUI
import MapKit
import Observation
import CoreLocation

// 游戏阶段状态
enum GamePhase {
    case setup
    case playing
    case gameOver
}

@MainActor
@Observable
final class GameManager {

    // MARK: - Game State
    var phase: GamePhase = .setup

    /// ✅ 不要用 Optional：Setup 一定会选一个默认区域 
    var selectedRegion: GameRegion = GameRegion.allRegions.first!

    // 缩圈相关
    var safeZone: SafeZone?
    private var gameTimer: Timer?

    // 玩家数据
    var currentUser: Player = .mockCurrentUser
    var otherPlayers: [Player] = Player.mockOthers

    // 导航相关
    var currentRoute: MKRoute?
    var trackingTarget: Player?
    var errorMessage: String?

    // 依赖
    let locationService = LocationService()

    // MARK: - Setup Lifecycle
    func onSetupAppear() {
        // 只在 setup 阶段做：请求权限 + 开始定位（用于推荐最近校区）
        locationService.requestPermission()
        locationService.start()

        // 如果拿得到定位，就推荐最近校区
        recommendNearestRegionIfPossible()
    }

    func recommendNearestRegionIfPossible() {
        guard phase == .setup else { return }
        guard let user = locationService.currentLocation else { return }

        let userLoc = CLLocation(latitude: user.latitude, longitude: user.longitude)

        if let nearest = GameRegion.allRegions.min(by: { a, b in
            let da = userLoc.distance(from: CLLocation(latitude: a.center.latitude, longitude: a.center.longitude))
            let db = userLoc.distance(from: CLLocation(latitude: b.center.latitude, longitude: b.center.longitude))
            return da < db
        }) {
            selectedRegion = nearest
        }
    }

    // MARK: - Game Flow
    func startGame() {
        // 1) 设置初始安全区
        safeZone = SafeZone(center: selectedRegion.center, radius: selectedRegion.initialRadius)

        // 2) 切到 playing
        withAnimation(.easeInOut) {
            phase = .playing
        }

        // 3) 游戏中继续定位（用于蓝点、追踪等）
        locationService.start()

        // 4) 开始缩圈
        startZoneShrinking()
    }

    func endGame() {
        // 结束：进入结算页
        stopZoneShrinking()
        currentRoute = nil
        trackingTarget = nil
        withAnimation(.easeInOut) {
            phase = .gameOver
        }
    }

    func backToSetup() {
        // 回到开局
        stopZoneShrinking()
        currentRoute = nil
        trackingTarget = nil
        safeZone = nil
        withAnimation(.easeInOut) {
            phase = .setup
        }
        // setup 阶段你可以选择继续定位以推荐，或停掉省电
        // 这里我选择继续跑，保证推荐功能可用
        locationService.start()
    }

    // MARK: - Zone Shrinking
    private func startZoneShrinking() {
        stopZoneShrinking()

        let tick: TimeInterval = 0.5
        let shrinkPerTick: CLLocationDistance = 5

        gameTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            guard let self else { return }

            // 切回 MainActor 再读写 safeZone
            Task { @MainActor in
                guard var zone = self.safeZone else { return }
                guard zone.radius > 100 else { return }

                zone.radius -= shrinkPerTick
                withAnimation(.easeInOut(duration: tick)) {
                    self.safeZone = zone
                }
            }
        }
    }


    private func stopZoneShrinking() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    // MARK: - Navigation
    func navigate(to player: Player) async {
        trackingTarget = player

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: player.coordinate))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            withAnimation(.easeInOut) {
                currentRoute = response.routes.first
            }
        } catch {
            errorMessage = "无法规划路线：\(error.localizedDescription)"
        }
    }

    func cancelNavigation() {
        withAnimation(.easeInOut) {
            currentRoute = nil
            trackingTarget = nil
        }
    }
}
