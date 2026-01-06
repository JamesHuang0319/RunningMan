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

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var locationTask: Task<Void, Never>?

    // MARK: - Init
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        authorizationStatus = locationManager.authorizationStatus
        refreshMessageFromAuth()
    }

    // MARK: - Permission Management
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
        // 有些情况下回调会稍后到；这里先同步刷新一次状态
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

    // MARK: - Start / Stop Location Updates
    
    func start() {
        // 无权限直接提示，不启动任务
        guard canUseLocation else {
            refreshMessageFromAuth()
            return
        }

        // 防止重复启动
        guard locationTask == nil else { return }
        lastErrorMessage = nil

        locationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if Task.isCancelled { return }

                    // iOS 18: 可用时读取诊断信息（获取更细致的错误原因）
                    await MainActor.run {
                        self.consumeDiagnosticsIfAvailable(update)
                    }

                    if let location = update.location {
                        // ✅ 核心逻辑：坐标转换
                        // 硬件返回的是 WGS-84，转为 GCJ-02 后再更新给 UI 和业务
                        let gcjLocation = LocationUtils.wgs84ToGcj02(
                            lat: location.coordinate.latitude,
                            lon: location.coordinate.longitude
                        )

                        await MainActor.run {
                            // 现在 currentLocation 持有的是纠偏后的火星坐标
                            self.currentLocation = gcjLocation
                        }
                    }
                }
            } catch is CancellationError {
                // 任务被取消，属正常流程
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

    // MARK: - One-shot Location (For UI Snapshots)
    
    /// 只取一次位置（例如：打开页面时锁定地图中心）
    /// - 不会停止现有的 liveUpdates 任务
    /// - 如果当前已有 currentLocation，直接返回缓存，避免等待
    func requestOneShotLocation(timeoutSeconds: Double = 3.0) async -> CLLocationCoordinate2D? {
        if let cached = currentLocation { return cached }
        guard canUseLocation else { return nil }

        do {
            var iterator = CLLocationUpdate.liveUpdates().makeAsyncIterator()
            let deadline = Date().addingTimeInterval(timeoutSeconds)

            while Date() < deadline {
                if let update = try await iterator.next(), let loc = update.location {
                    // ✅ OneShot 同样需要转换，保持坐标系一致
                    return LocationUtils.wgs84ToGcj02(
                        lat: loc.coordinate.latitude,
                        lon: loc.coordinate.longitude
                    )
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        refreshMessageFromAuth()

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // ✅ 授权获得后自动恢复定位
            start()

        case .denied, .restricted:
            // 权限被拒绝/受限：停止定位并清空数据
            stop()
            currentLocation = nil

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Helpers & Diagnostics

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

    /// iOS 18: 从 CLLocationUpdate 读取“不给位置”的详细原因
    @MainActor
    private func consumeDiagnosticsIfAvailable(_ update: CLLocationUpdate) {
        if #available(iOS 18.0, *) {
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                lastErrorMessage = "定位权限被拒绝：请到系统设置中开启定位权限。"
            } else if update.authorizationRestricted {
                lastErrorMessage = "定位权限受限：可能由系统策略限制。"
            } else if update.insufficientlyInUse {
                lastErrorMessage = "定位不可用：App 需要在使用中才能获取位置。"
            } else if update.locationUnavailable {
                lastErrorMessage = "位置暂不可用：请检查 GPS/网络或到室外重试。"
            } else if update.serviceSessionRequired {
                lastErrorMessage = "定位需要 Service Session（iOS 18）：请检查定位会话设置。"
            } else if update.accuracyLimited {
                // lastErrorMessage = "定位精度受限：可在系统设置开启“精确位置”。"
            } else {
                // 诊断无异常
            }
        }
    }
}

// MARK: - Location Utils (Coordinate Transform)

struct LocationUtils {

    static let a = 6378245.0
    static let ee = 0.00669342162296594329

    /// 将 WGS-84 (国际标准/硬件GPS) 转换为 GCJ-02 (火星坐标/高德/腾讯/国内AppleMap)
    static func wgs84ToGcj02(lat: Double, lon: Double) -> CLLocationCoordinate2D {
        if outOfChina(lat: lat, lon: lon) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        var dLat = transformLat(x: lon - 105.0, y: lat - 35.0)
        var dLon = transformLon(x: lon - 105.0, y: lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(
            latitude: lat + dLat,
            longitude: lon + dLon
        )
    }

    /// 简易判断是否在中国境外
    static func outOfChina(lat: Double, lon: Double) -> Bool {
        if lon < 72.004 || lon > 137.8347 { return true }
        if lat < 0.8293 || lat > 55.8271 { return true }
        return false
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
