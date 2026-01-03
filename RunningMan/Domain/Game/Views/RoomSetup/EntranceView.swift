//
//  EntranceView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/26.
//


import MapKit
import SwiftUI
import CoreLocation
import Combine

struct EntranceView: View {
    @Environment(GameStore.self) var game
    @Environment(ProfileStore.self) var profile
    @Environment(AuthStore.self) var auth

    @State private var joinId: String = ""
    @State private var isBusy = false
    @State private var radarPhase: Double = 0.0

    // ✅ FIX: 不要用 .userLocation 相机（会触发系统蓝点 + 持续跟随）
    // 先用 .automatic，进入页面后我们会“锁定一次”成 .camera(...)，但保持地球远景效果
    @State private var cameraPosition: MapCameraPosition = .automatic

    // ✅ FIX: 只锁一次相机，锁定后地图中心不再变，雷达视觉固定
    @State private var didLockCameraOnce = false
    @State private var lockedCoordinate: CLLocationCoordinate2D? = nil

    // ✅ NEW: Entrance 专用定位器（只为了锁相机精度，不影响你全局 LocationService）
    @StateObject private var entranceLoc = EntranceFixLocationProvider()

    private var normalizedJoinId: String {
        joinId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isJoinIdValid: Bool {
        UUID(uuidString: normalizedJoinId) != nil
    }

    private var brandGradient: LinearGradient {
        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 头像 path / signedURL（复用 ProfileView 的取值方式：读缓存命中 KF cacheKey=path）
    private var currentAvatarPath: String? {
        guard let me = profile.me else { return nil }
        return profile.avatarPath(for: me)
    }

    private var currentSignedURL: URL? {
        guard let path = currentAvatarPath else { return nil }
        return profile.signedURL(forPath: path)
    }

    private var displayAgentName: String {
        if let uid = auth.userId {
            if let name = profile.me?.username, !name.isEmpty {
                return name.uppercased()
            }
            return "RUNNER\(uid.uuidString.prefix(4))".uppercased()
        }
        return "AGENT"
    }

    var body: some View {
        ZStack {
            // 1. 底层地图 - Realistic 卫星图
            // ✅ FIX: 不用 showsUserLocation 参数（你 Map(position:) 这套 initializer 不支持）
            // ✅ FIX: 不用 .userLocation 相机 => 蓝点不会被“相机语义”强制显示
            Map(position: $cameraPosition)
                .mapStyle(.imagery(elevation: .realistic))
                .disabled(true) // 彻底锁定手势
                .ignoresSafeArea()
                .overlay {
                    RadialGradient(
                        colors: [.clear, Color(hex: "0F2027").opacity(0.12)],
                        center: .center,
                        startRadius: 200,
                        endRadius: 700
                    )
                    .ignoresSafeArea()
                }

            // 2. 雷达动画（保持原有）
            radarAnimation

            // 3. UI 内容层
            VStack(spacing: 0) {
                topAgentHUD
                    .padding(.top, 10)

                Spacer()

                bottomControlPanel
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            // 启动雷达动画
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                radarPhase = 1.0
            }
        }
        // ✅ FIX: 打开时锁一次，但“等更准的定位”再锁（避免第一帧粗定位造成偏移）
        // ✅ 同时锁到“地球远景”距离，保留夜景灯光那种帅效果
        .task {
            await lockCameraOnceWithBetterAccuracy()
        }
        // ✅ 头像/昵称预热（对齐 ProfileView：优先读缓存）
        .task {
            guard let uid = auth.userId else { return }
            if profile.me?.id != uid {
                await profile.loadMe(userId: uid, usePersistedFirst: true)
            }
        }
        .overlay(alignment: .center) {
            if isBusy {
                loadingOverlay
            }
        }
    }

    // MARK: - Components

    private var topAgentHUD: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                    .background(Circle().fill(.ultraThinMaterial))
                    .frame(width: 44, height: 44)

                // ✅ 用 AvatarView(KFImage) 命中缓存（cacheKey=path）
                AvatarView(
                    size: 40,
                    shape: .circle,
                    placeholderSystemName: "person.crop.circle.fill",
                    localPreview: nil,
                    path: currentAvatarPath,
                    signedURL: currentSignedURL,
                    onTap: nil
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayAgentName)
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("ONLINE - READY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.caption2)
                    Text("GPS LOCKED").font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(.blue)

                Text(Date().formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }

    private var radarAnimation: some View {
        ZStack {
            Circle()
                .stroke(brandGradient.opacity(0.7), lineWidth: 2)
                .frame(width: 100, height: 100)
                .scaleEffect(1 + radarPhase * 3)
                .opacity(1 - radarPhase)

            Circle()
                .stroke(brandGradient.opacity(0.5), lineWidth: 1.5)
                .frame(width: 100, height: 100)
                .scaleEffect(1 + radarPhase * 2)
                .opacity(1 - radarPhase * 0.8)

            Circle()
                .fill(brandGradient)
                .frame(width: 16, height: 16)
                .shadow(color: .blue.opacity(0.8), radius: 12)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
        }
        .allowsHitTesting(false)
    }

    private var bottomControlPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle().frame(width: 12, height: 2).foregroundStyle(.blue)
                Text("MISSION SETUP")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.blue)
                    .tracking(2)
                Spacer()
            }
            .padding(.bottom, -4)

            Button {
                Task { await createRoom() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.viewfinder")
                    Text("建立行动代号 (创建房间)")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(brandGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(isBusy)

            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
                    TextField("输入 UUID 加入已有房间", text: $joinId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.system(.footnote, design: .monospaced))
                        .submitLabel(.join)
                        .onSubmit { Task { await joinRoom() } }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await joinRoom() }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isJoinIdValid ? AnyShapeStyle(brandGradient) : AnyShapeStyle(Color.gray.opacity(0.3)))
                }
                .disabled(isBusy || !isJoinIdValid)
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .padding(.bottom, 30)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.white.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView().tint(.blue).scaleEffect(1.5)
                Text("ESTABLISHING UPLINK...")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Actions（不改业务逻辑）
    private func createRoom() async {
        guard !isBusy else { return }
        withAnimation { isBusy = true }
        await game.createRoomAndJoin()
        isBusy = false
    }

    private func joinRoom() async {
        guard !isBusy, isJoinIdValid else { return }
        withAnimation { isBusy = true }
        await game.joinRoom(roomId: UUID(uuidString: normalizedJoinId)!)
        joinId = ""
        isBusy = false
    }

    // MARK: - ✅ 相机锁定：等更准再锁一次（UI-only）
    private func lockCameraOnceWithBetterAccuracy() async {
        guard !didLockCameraOnce else { return }
        didLockCameraOnce = true

        // 目标：尽量等到 <= 65m 的精度；最多等 1.5s（不影响体验）
        let accuracyTarget: CLLocationAccuracy = 65
        let maxWaitNanos: UInt64 = 1_500_000_000

        entranceLoc.requestStart()

        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < maxWaitNanos {
            if let loc = entranceLoc.latestLocation {
                // 精度足够好就锁
                if loc.horizontalAccuracy > 0 && loc.horizontalAccuracy <= accuracyTarget {
                    lockedCoordinate = loc.coordinate
                    lockCamera(to: loc.coordinate) // ✅ 地球远景相机
                    entranceLoc.stop()
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        // 超时兜底：用最后一条（即使精度一般也比没有强）
        if let loc = entranceLoc.latestLocation {
            lockedCoordinate = loc.coordinate
            lockCamera(to: loc.coordinate) // ✅ 地球远景相机
        }

        entranceLoc.stop()
    }

    // MARK: - ✅ 地球视角相机（保留“夜景灯光”的帅效果）
    private func lockCamera(to coord: CLLocationCoordinate2D) {
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: coord,

                // ✅ 关键：远景距离，才能看到“地球+夜景灯光”整体效果
                
                // 可调范围：6_000_000 ~ 15_000_000
                distance: 12_000_000,
                // ✅ 给一点旋转更帅（不喜欢就改 0）
                heading: 0,
                // ✅ 增加倾角更有电影感
                pitch: 25,
            )
        )
    }
}

// MARK: - ✅ NEW: Entrance 专用定位器（只用于锁相机，不影响全局）
final class EntranceFixLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    // 只存最后一条
    @MainActor @Published var latestLocation: CLLocation? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestStart() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.latestLocation = locations.last
        }
    }
}
