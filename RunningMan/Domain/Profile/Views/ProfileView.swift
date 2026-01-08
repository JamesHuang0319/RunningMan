//
//  ProfileView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ProfileStore.self) private var profileStore

    // MARK: - State (业务逻辑完全保留)
    @State private var pickedItem: PhotosPickerItem?
    @State private var localPreview: Image?
    @State private var isSavingAvatar = false
    @State private var showPicker = false

    @State private var isEditingName = false
    @State private var editingName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var isSavingName = false

    @State private var isManagingHonors = false
    @State private var showAllAchievements = false

    // ✅ 退出确认状态
    @State private var showSignOutConfirm = false

    private let initialBackground = Color(hex: "F2F4F7")

    var body: some View {
        NavigationStack {
            ZStack {
                initialBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader

                        if let err = profileStore.error, !err.isEmpty {
                            errorCard(err)
                        }

                        statsSection

                        achievementsSection

                        settingsSection

                        // ✅ 退出按钮
                        if auth.userId != nil {
                            signOutButton
                        }

                        // ✅ 彻底解决 TabBar 误触：
                        // 这里增加一个巨大的透明占位（140pt），确保“退出登录”永远在 TabBar 之上很远的地方
                        Color.clear.frame(height: 140)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("个人中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .refreshable {
                guard let uid = auth.userId else { return }
                await profileStore.loadMe(userId: uid, forceRefreshAvatar: true)
            }
            .task {
                guard let uid = auth.userId else { return }
                if profileStore.me?.id != uid {
                    await profileStore.loadMe(
                        userId: uid,
                        usePersistedFirst: true
                    )
                }
                if editingName.isEmpty {
                    editingName =
                        profileStore.me?.username ?? defaultName(for: uid)
                }
            }
            .photosPicker(
                isPresented: $showPicker,
                selection: $pickedItem,
                matching: .images
            )
            .onChange(of: pickedItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePickedAvatar(newItem) }
            }
            .onTapGesture {
                withAnimation { isManagingHonors = false }
            }
            .confirmationDialog(
                "确定要退出登录吗？",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("退出登录", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 1. Profile Header
    private var profileHeader: some View {
        HStack(spacing: 20) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(
                    size: 84,
                    shape: .circle,
                    placeholderSystemName: "person.circle.fill",
                    localPreview: localPreview,
                    path: currentAvatarPath,
                    signedURL: currentSignedURL,
                    onTap: {
                        guard auth.userId != nil else { return }
                        showPicker = true
                    }
                )

                if auth.userId != nil {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.blue, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if auth.userId == nil {
                    Text("未登录").font(.title2.bold()).foregroundStyle(.primary)
                } else if isEditingName {
                    HStack {
                        TextField("输入昵称", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { Task { await saveName() } }

                        if isSavingName {
                            ProgressView().tint(.blue)
                        } else {
                            Button {
                                Task { await saveName() }
                            } label: {
                                Image(systemName: "checkmark.circle.fill").font(
                                    .title2
                                ).foregroundStyle(.green)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        UIImpactFeedbackGenerator(style: .medium)
                            .impactOccurred()
                        withAnimation {
                            isEditingName = true
                            nameFieldFocused = true
                            if let uid = auth.userId {
                                editingName =
                                    profileStore.me?.username
                                    ?? defaultName(for: uid)
                            }
                        }
                    }

                    Text("ID: \(displaySubline)")
                        .font(
                            .system(
                                size: 10,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.05), in: Capsule())
                }
            }
            Spacer()
        }
        .initialCardStyle()
    }

    // MARK: - 2. Stats Section
    private var statsSection: some View {
        HStack(spacing: 12) {
            statItem(
                title: "场次",
                value: profileStore.totalGamesString,
                unit: "场",
                icon: "flag.checkered"
            )
            statItem(
                title: "胜率",
                value: profileStore.winRateString,
                unit: "%",
                icon: "chart.line.uptrend.xyaxis"
            )
            statItem(
                title: "里程",
                value: profileStore.totalDistanceString,
                unit: "km",
                icon: "figure.run"
            )
        }
    }

    private func statItem(
        title: String,
        value: String,
        unit: String,
        icon: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption2.bold())
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.primary)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .initialCardStyle(cornerRadius: 16)
    }

    // MARK: - 3. Achievements (动画修复点)
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("荣誉陈列室").font(.headline).foregroundStyle(.primary)
                Spacer()
                Button {
                    // 切换管理状态
                    isManagingHonors.toggle()
                } label: {
                    Text(isManagingHonors ? "完成" : "管理")
                        .font(.subheadline)
                        .foregroundStyle(isManagingHonors ? .blue : .secondary)
                }
            }

            if profileStore.homeAchievements.isEmpty {
                // ✅ 重新设计的精致占位图
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button {
                            showAllAchievements = true
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(
                                        style: StrokeStyle(
                                            lineWidth: 1.5,
                                            dash: [4]
                                        )
                                    )
                                    .foregroundStyle(.gray.opacity(0.3))
                                    .frame(width: 52, height: 52)  // 尺寸更小巧
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.gray.opacity(0.6))
                            }
                        }
                        Text("点击 + 开启荣誉墙").font(.caption2).foregroundStyle(
                            .secondary.opacity(0.7)
                        )
                    }
                    Spacer()
                }
                .padding(.vertical, 10)  // 压缩垂直高度
            } else {

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(profileStore.homeAchievements) { item in
                            // ✅ 调用内部组件
                            AchievementBadge(
                                item: item,
                                isEditing: isManagingHonors
                            ) {
                                if let dbID = item.dbID {
                                    Task {
                                        await profileStore
                                            .toggleAchievementVisibility(
                                                dbID: dbID,
                                                hide: true
                                            )
                                    }
                                }
                            }
                        }
                        if profileStore.homeAchievements.isEmpty {
                            Text("点击 + 号展示荣誉").font(.caption).foregroundStyle(
                                .secondary
                            )
                        }
                        Button {
                            showAllAchievements = true
                        } label: {
                            plusBadgePlaceholder
                        }
                    }
                    .padding(.all, 10)
                }
            }
        }
        .initialCardStyle(cornerRadius: 20)
        .sheet(isPresented: $showAllAchievements) { AllAchievementsView() }
    }

    private var plusBadgePlaceholder: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.05)).frame(
                    width: 64,
                    height: 64
                )
                .overlay(
                    Circle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.gray.opacity(0.3))
                )
                Image(systemName: "plus").font(.title2).foregroundStyle(.gray)
            }
            Text("添加").font(.caption2).foregroundStyle(.clear)
        }
    }

    // MARK: - 4. Settings Section
    private var settingsSection: some View {
        VStack(spacing: 0) {
            Group {
                settingRow(icon: "gearshape.fill", title: "通用设置", color: .gray)
                divider
                settingRow(
                    icon: "shield.lefthalf.filled",
                    title: "账号安全",
                    color: .blue
                )
                divider
                settingRow(icon: "bell.fill", title: "通知管理", color: .red)
                divider
                settingRow(icon: "lock.fill", title: "隐私与权限", color: .green)
            }
            Rectangle().fill(Color.black.opacity(0.02)).frame(height: 8)
            Group {
                // ✅ 修改：重命名为清理缓存，更换图标
                settingRow(
                    icon: "trash.fill",
                    title: "清理缓存",
                    color: .purple,
                    value: "2 MB"
                )
                divider
                settingRow(icon: "envelope.fill", title: "意见反馈", color: .orange)
                divider
                settingRow(
                    icon: "info.circle.fill",
                    title: "关于我们",
                    color: .cyan,
                    value: "V 1.0.0"
                )
            }
        }
        .initialCardStyle(cornerRadius: 16, padding: 0)
    }

    private var divider: some View {
        Divider().background(Color.black.opacity(0.05)).padding(.leading, 56)
    }

    private func settingRow(
        icon: String,
        title: String,
        color: Color,
        value: String? = nil
    ) -> some View {
        Button {
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                        color
                    )
                    Image(systemName: icon).font(
                        .system(size: 14, weight: .semibold)
                    ).foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                Text(title).font(.subheadline).foregroundStyle(.primary)
                Spacer()
                if let value = value {
                    Text(value).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(
                    .system(size: 12, weight: .bold)
                ).foregroundStyle(.secondary.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 5. 退出按钮（带坐标检测的加固版）
    private var signOutButton: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let screenHeight = UIScreen.main.bounds.height
            // 🛑 核心阈值：如果按钮底部进入屏幕底部 10x z0 像素以内，认为是被 TabBar 遮挡
            let isCoveredByTab = frame.maxY > (screenHeight - 100)

            Button {
                showSignOutConfirm = true
            } label: {
                Text("退出登录")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red.opacity(0.1), lineWidth: 1)
                    )
                    // 视觉反馈：在遮挡区域自动变淡，告知用户此处不可点
                    .opacity(isCoveredByTab ? 0.2 : 1.0)
                    .scaleEffect(isCoveredByTab ? 0.95 : 1.0)
            }
            // ✅ 关键：当按钮在 TabBar 区域时，不响应任何点击，防止穿透误触
            .allowsHitTesting(!isCoveredByTab)
            .animation(.spring(), value: isCoveredByTab)
        }
        .frame(height: 54)  // 必须固定容器高度，否则 ScrollView 布局会坍塌
    }

    // MARK: - Logic Helpers (全保留)
    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(
                .red
            )
            Text(text).font(.footnote).foregroundStyle(.red)
            Spacer()
        }
        .padding(12).background(
            Color.red.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var currentAvatarPath: String? {
        guard let me = profileStore.me else { return nil }
        return profileStore.avatarPath(for: me)
    }

    private var currentSignedURL: URL? {
        guard let path = currentAvatarPath else { return nil }
        return profileStore.signedURL(forPath: path)
    }

    private var displayName: String {
        guard let uid = auth.userId else { return "未登录" }
        if let name = profileStore.me?.username, !name.isEmpty { return name }
        return defaultName(for: uid)
    }

    private func defaultName(for uid: UUID) -> String {
        "Runner\(uid.uuidString.prefix(4))"
    }
    private var displaySubline: String {
        guard let uid = auth.userId else { return "GUEST" }
        return String(uid.uuidString.prefix(8)).uppercased()
    }

    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard let uid = auth.userId else { return }
        isSavingAvatar = true
        defer { isSavingAvatar = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                let img = UIImage(data: raw),
                let jpeg = img.jpegData(compressionQuality: 0.85)
            else { return }
            await MainActor.run { localPreview = Image(uiImage: img) }
            await profileStore.updateMyAvatar(userId: uid, jpegData: jpeg)
            await MainActor.run {
                localPreview = nil
                pickedItem = nil
            }
        } catch { await MainActor.run { pickedItem = nil } }
    }

    private func saveName() async {
        guard let uid = auth.userId else { return }
        let newName = editingName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !newName.isEmpty else { return }
        isSavingName = true
        await profileStore.updateMyUsername(userId: uid, username: newName)
        await MainActor.run {
            isSavingName = false
            isEditingName = false
            nameFieldFocused = false
        }
    }

    // MARK: - ✅ 勋章组件修复版
    struct AchievementBadge: View {
        let item: AchievementItem
        let isEditing: Bool
        let onDelete: () -> Void

        // 使用局部私有状态控制晃动，防止被父视图刷新干扰
        @State private var internalWobble = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    ZStack {
                        Circle().fill(item.color.gradient.opacity(0.1)).frame(
                            width: 64,
                            height: 64
                        )
                        Image(systemName: item.icon).font(.title)
                            .foregroundStyle(item.color.gradient)
                    }
                    // ✅ 修复点：使用 internalWobble 驱动，确保动画持续
                    .rotationEffect(
                        .degrees(isEditing ? (internalWobble ? -2.5 : 2.5) : 0)
                    )
                    .onChange(of: isEditing) { _, newValue in
                        if newValue {
                            startAnimation()
                        } else {
                            internalWobble = false
                        }
                    }
                    .onAppear {
                        if isEditing { startAnimation() }
                    }

                    if isEditing {
                        Button(action: onDelete) {
                            Image(systemName: "minus").font(
                                .system(size: 10, weight: .bold)
                            ).foregroundStyle(.white)
                                .padding(6).background(Color.red, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .offset(x: -6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(item.name).font(.caption2.bold()).foregroundStyle(
                    .secondary
                )
            }
        }

        private func startAnimation() {
            // 使用线性无限循环，确保晃动手感丝滑
            withAnimation(
                .linear(duration: 0.12).repeatForever(autoreverses: true)
            ) {
                internalWobble = true
            }
        }
    }

}

// MARK: - Preview
#Preview {
    ProfileView().environment(AuthStore()).environment(ProfileStore())
}

// MARK: - Modifier
struct InitialCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat
    func body(content: Content) -> some View {
        content.padding(padding).background(Color.white)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func initialCardStyle(cornerRadius: CGFloat = 20, padding: CGFloat = 16)
        -> some View
    {
        modifier(
            InitialCardModifier(cornerRadius: cornerRadius, padding: padding)
        )
    }
}
