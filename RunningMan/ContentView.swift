//
//  ContentView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/7.
//

import MapKit
import SwiftUI

struct ContentView: View {
    let cameraPostion: MapCameraPosition = .region(
        .init(
            center: .init(latitude: 37.3346, longitude: -122.0090),
            latitudinalMeters: 130000,
            longitudinalMeters: 130000,
        )
    )

    let locationManager = CLLocationManager()
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isShowingLookAround = false
    @State private var route: MKRoute?

    @State private var strokePhase: CGFloat = 0.0

    var body: some View {
        Map {
            //            Marker("App visitor Center", systemImage: "laptopcomputer", coordinate: .appleVisitorCenter)
            //            Marker("Panama Park", systemImage: "tree.fill", coordinate: .panamaPark)

            Annotation(
                "App visitor Center",
                coordinate: .appleVisitorCenter,
                anchor: .center
            ) {
                Image(systemName: "laptopcomputer")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .padding(7)
                    .background(.pink.gradient, in: .circle)
                    .contextMenu {
                        Button("Open Look Around", systemImage: "binoculars") {
                            Task {
                                lookAroundScene = await getLookAroundScene(
                                    from: .appleVisitorCenter
                                )
                                if lookAroundScene != nil {
                                    isShowingLookAround = true
                                }
                            }
                        }
                        Button(
                            "Get Directions",
                            systemImage: "arrow.turn.down.right"
                        ) {
                            getDirections(to: .appleVisitorCenter)
                        }
                    }
            }

            Annotation("Panama Park", coordinate: .panamaPark, anchor: .bottom)
            {
                Image(systemName: "tree.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .padding(7)
                    .background(.green.gradient, in: .circle)
                    .contextMenu {
                        Button("Open Look Around", systemImage: "binoculars") {
                            Task {
                                lookAroundScene = await getLookAroundScene(
                                    from: .panamaPark
                                )
                                if lookAroundScene != nil {
                                    isShowingLookAround = true
                                }
                            }
                        }
                        Button(
                            "Get Directions",
                            systemImage: "arrow.turn.down.right"
                        ) {
                            getDirections(to: .panamaPark)
                        }
                    }

            }
            Annotation(
                "中南大学岳麓山校区",
                coordinate: .centralSouthU,
                anchor: .center
            ) {
                Image(systemName: "house")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .padding(7)
                    .background(.pink.gradient, in: .circle)
                    .contextMenu {
                        Button("Open Look Around", systemImage: "binoculars") {
                            Task {
                                lookAroundScene = await getLookAroundScene(
                                    from: .centralSouthU
                                )
                                if lookAroundScene != nil {
                                    isShowingLookAround = true
                                }
                            }
                        }
                        Button(
                            "Get Directions",
                            systemImage: "arrow.turn.down.right"
                        ) {
                            getDirections(to: .centralSouthU)
                        }
                    }
            }

            Annotation("湖南大学东方红校区", coordinate: .hunanU, anchor: .bottom) {
                Image(systemName: "globe.americas")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .padding(7)
                    .background(.green.gradient, in: .circle)
                    .contextMenu {
                        Button("Open Look Around", systemImage: "binoculars") {
                            Task {
                                lookAroundScene = await getLookAroundScene(
                                    from: .hunanU
                                )
                                if lookAroundScene != nil {
                                    isShowingLookAround = true
                                }
                            }
                        }
                        Button(
                            "Get Directions",
                            systemImage: "arrow.turn.down.right"
                        ) {
                            getDirections(to: .hunanU)
                        }
                    }
            }

            UserAnnotation()
            // 放在 Map 闭包的最后面
            if let route {
                // 1. 底层光晕（模拟发光效果）
                MapPolyline(route)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan.opacity(0.5), .purple.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 8  // 比主线宽，制造光晕感
                    )

                // 2. 顶层流动的主线（Apple Intelligence 渐变 + 虚线流动动画）
                MapPolyline(route)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple, .pink],  // 经典的 AI 渐变色
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [10, 10],  // 虚线模式：10点实线，10点空白
                            dashPhase: strokePhase  // 关键：通过改变这个值实现流动
                        )
                    )
            }

        }
        .tint(.pink)
        .onAppear {
            // 启动定位权限请求
            locationManager.requestWhenInUseAuthorization()

            // 启动线条流动动画
            // 这里的 duration 控制流动速度，越小越快
            withAnimation(
                .linear(duration: 1.5).repeatForever(autoreverses: false)
            ) {
                strokePhase -= 20  // 向后移动相位，形成向前流动的视觉效果
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
        .mapStyle(.standard(elevation: .realistic, showsTraffic: true))
        .lookAroundViewer(
            isPresented: $isShowingLookAround,
            initialScene: lookAroundScene
        )
    }

    func getLookAroundScene(from coordinate: CLLocationCoordinate2D) async
        -> MKLookAroundScene?
    {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        do {
            let scene = try await request.scene
            if scene == nil {
                print("坐标 \(coordinate) 附近没有 Look Around 数据")
            }
            return scene
        } catch {
            print("获取失败: \(error.localizedDescription)")

            return nil
        }
    }

    func getUserLocation() async -> CLLocationCoordinate2D? {
        let updates = CLLocationUpdate.liveUpdates()
        do {
            let update = try await updates.first {
                $0.location?.coordinate != nil
            }
            return update?.location?.coordinate
        } catch {
            print("Cannot get User Location")
            return nil
        }
    }

    func getDirections(to destination: CLLocationCoordinate2D) {
        Task {
            // 1. 获取用户位置
            guard let userLocation = await getUserLocation() else {
                print("❌ 错误：无法获取用户当前位置 (getUserLocation 返回 nil)")
                return
            }

            // 2. 配置请求
            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = MKMapItem(
                placemark: .init(coordinate: destination)
            )
            request.transportType = .any

            // 🖨️【调试开始】打印请求参数
            print("\n-------- 🚀 发起导航请求 --------")
            print(
                "📍 起点 (User): \(userLocation.latitude), \(userLocation.longitude)"
            )
            print(
                "🏁 终点 (Dest): \(destination.latitude), \(destination.longitude)"
            )
            print(
                "🚗 交通方式 rawValue: \(request.transportType.rawValue) (1=驾车, 2=步行, 4=公交)"
            )
            print("----------------------------------")

            do {
                // 3. 计算路线
                let directions = try await MKDirections(request: request)
                    .calculate()

                // 4. 回到主线程更新 UI (必须!)
                await MainActor.run {
                    withAnimation(.easeInOut) {  // 让路线出现时有个淡入效果
                        self.route = directions.routes.first
                    }
                    if let r = self.route {
                        print(
                            "✅ 成功! 找到路线，距离: \(String(format: "%.2f", r.distance / 1000)) 公里"
                        )
                    }
                }
            } catch {
                // 🖨️【调试报错】打印详细错误信息
                print("\n❌❌❌ 导航计算失败 ❌❌❌")
                print("1. 错误描述: \(error.localizedDescription)")

                // 打印具体的起点终点，方便检查是否跨国
                if let s = request.source?.placemark.coordinate,
                    let d = request.destination?.placemark.coordinate
                {
                    print(
                        "2. 尝试路径: (\(s.latitude), \(s.longitude)) -> (\(d.latitude), \(d.longitude))"
                    )
                }

                // 帮助分析常见错误
                let nsError = error as NSError
                if nsError.domain == MKErrorDomain && nsError.code == 4 {
                    print(
                        "💡 分析: Error 4 通常意味着起点和终点之间没有路 (例如跨越海洋)，或者距离太远无法步行到达。"
                    )
                }
                print("----------------------------------\n")
            }
        }
    }
}

#Preview {
    ContentView()
}

extension CLLocationCoordinate2D {
    static let appleHQ = CLLocationCoordinate2D(
        latitude: 37.3346,
        longitude: -122.0090
    )
    static let appleVisitorCenter = CLLocationCoordinate2D(
        latitude: 37.332693,
        longitude: -122.005493
    )
    static let panamaPark = CLLocationCoordinate2D(
        latitude: 37.347730,
        longitude: -122.018715
    )
    // 长沙大学城 (以大学城地铁站/阜埠河附近为中心)
    static let universityTown = CLLocationCoordinate2D(
        latitude: 28.164315,
        longitude: 112.943105
    )

    // 中南大学 (本部/岳麓山校区 - 靠近新校区大门)
    static let centralSouthU = CLLocationCoordinate2D(
        latitude: 28.166300,
        longitude: 112.936800
    )

    // 湖南大学 (东方红广场/毛主席像)
    static let hunanU = CLLocationCoordinate2D(
        latitude: 28.178300,
        longitude: 112.942800
    )

    // 湖南师范大学 (二里半/图书馆附近)
    static let hunanNormalU = CLLocationCoordinate2D(
        latitude: 28.186500,
        longitude: 112.944300
    )
}
