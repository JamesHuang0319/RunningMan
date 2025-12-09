//
//  LocationService.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/9.
//

import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: - Public State
    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastErrorMessage: String?

    // MARK: - Private
    private let locationManager = CLLocationManager()
    private var locationTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
        refreshMessageFromAuth()
    }

    // MARK: - Permission
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
        // 有些情况下回调会稍后到；这里先同步刷新一次
        authorizationStatus = locationManager.authorizationStatus
        refreshMessageFromAuth()
    }

    var canUseLocation: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    // MARK: - Start / Stop
    func start() {
        // 无权限直接提示，不启动任务
        guard canUseLocation else {
            refreshMessageFromAuth()
            return
        }

        guard locationTask == nil else { return }
        lastErrorMessage = nil

        locationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if Task.isCancelled { return }

                    // iOS 18: 可用时读取诊断（更细原因）
                    await MainActor.run {
                        self.consumeDiagnosticsIfAvailable(update)
                    }

                    if let location = update.location {
                        await MainActor.run {
                            self.currentLocation = location.coordinate
                        }
                    }
                }
            } catch is CancellationError {
                // 正常取消
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "❌ 定位服务出错：\(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        locationTask?.cancel()
        locationTask = nil
    }

    // MARK: - CLLocationManagerDelegate (最稳的权限变化监听)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        refreshMessageFromAuth()

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // ✅ 建议：授权后自动恢复定位（你也可以注释掉改为手动）
            start()

        case .denied, .restricted:
            // 权限被拒绝/受限：停定位并清空
            stop()
            currentLocation = nil

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Helpers
    private func refreshMessageFromAuth() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            lastErrorMessage = nil
        case .denied:
            lastErrorMessage = "定位权限已关闭：请到 设置 → 隐私与安全 → 定位服务 中开启。"
        case .restricted:
            lastErrorMessage = "定位权限受限：可能由家长控制或系统策略限制。"
        case .notDetermined:
            lastErrorMessage = nil
        @unknown default:
            lastErrorMessage = "定位权限状态未知，请检查系统设置。"
        }
    }

    /// iOS 18: 从 CLLocationUpdate 读取“不给位置”的细原因（可选但很强）
    @MainActor
    private func consumeDiagnosticsIfAvailable(_ update: CLLocationUpdate) {
        if #available(iOS 18.0, *) {
            // 注意：这些并不等于“授权状态”，而是更细的诊断原因
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                lastErrorMessage = "定位权限被拒绝：请到系统设置中开启定位权限。"
            } else if update.authorizationRestricted {
                lastErrorMessage = "定位权限受限：可能由系统策略限制。"
            } else if update.insufficientlyInUse {
                lastErrorMessage = "定位不可用：App 需要在使用中才能获取位置。"
            } else if update.locationUnavailable {
                lastErrorMessage = "位置暂不可用：请检查 GPS/网络或到室外重试。"
            } else if update.serviceSessionRequired {
                // 你后面如果要后台/更强导航能力，可能会用到 CLServiceSession
                lastErrorMessage = "定位需要 Service Session（iOS 18）：请检查定位会话设置。"
            } else if update.accuracyLimited {
                // 是否提示看你需求；很多情况下不必打扰用户
                // lastErrorMessage = "定位精度受限：可在系统设置开启“精确位置”。"
            } else {
                // 诊断没有问题：不强制清空 lastErrorMessage
                // 如果你想“只要正常就清空”，可以打开：
                // if canUseLocation { lastErrorMessage = nil }
            }
        }
    }
}



