//
//  ProfileView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//
import PhotosUI
import SwiftUI

// MARK: - Model
struct AchievementItem: Identifiable, Equatable {
    let id = UUID()
    let color: Color
    let icon: String
    let name: String
}

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
    @State private var myAchievements: [AchievementItem] = [
        AchievementItem(color: .orange, icon: "trophy.fill", name: "首胜"),
        AchievementItem(
            color: .purple,
            icon: "figure.run.circle.fill",
            name: "疾行者"
        ),
        AchievementItem(color: .blue, icon: "bolt.fill", name: "闪电侠"),
    ]

    // ✅ 回退到右图的背景颜色
    private let initialBackground = Color(hex: "F2F4F7")

    var body: some View {
        NavigationStack {
            ZStack {
                // 1. 背景层
                initialBackground.ignoresSafeArea()

                // 2. 内容层
                ScrollView {
                    // ✅ 还原右图的间距感：VStack spacing 20
                    VStack(spacing: 20) {
                        // 头部卡片
                        profileHeader

                        // 错误提示
                        if let err = profileStore.error, !err.isEmpty {
                            errorCard(err)
                        }

                        // 数据项卡片
                        statsSection

                        // 荣誉陈列室
                        achievementsSection

                        // 设置列表
                        settingsSection

                        // 退出按钮
                        if auth.userId != nil {
                            signOutButton
                        }

                        Color.clear.frame(height: 80)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("个人中心")  // 同步右图标题
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
        }
    }

    // MARK: - 1. Profile Header (回退 84 尺寸)
    private var profileHeader: some View {
        HStack(spacing: 20) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(
                    size: 84,  // ✅ 还原初始尺寸
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

                if isSavingAvatar {
                    Text("更新头像中...").font(.caption2).foregroundStyle(.blue)
                }
            }
            Spacer()
        }
        .initialCardStyle()  // ✅ 使用还原后的卡片样式
    }

    // MARK: - 2. Stats Section
    private var statsSection: some View {
        HStack(spacing: 12) {
            statItem(title: "场次", value: "0", unit: "场", icon: "flag.checkered")
            statItem(
                title: "胜率",
                value: "--",
                unit: "%",
                icon: "chart.line.uptrend.xyaxis"
            )
            statItem(title: "里程", value: "0.0", unit: "km", icon: "figure.run")
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

    // MARK: - 3. Achievements (修复版)
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("荣誉陈列室").font(.headline).foregroundStyle(.primary)
                Spacer()
                Button {
                    // 使用显式动画切换状态，让转场更丝滑
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7))
                    {
                        isManagingHonors.toggle()
                    }
                } label: {
                    Text(isManagingHonors ? "完成" : "管理")
                        .font(.subheadline)
                        .foregroundStyle(isManagingHonors ? .blue : .secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {  // 稍微增加一点间距
                    ForEach(myAchievements) { item in
                        AchievementBadge(
                            item: item,
                            isEditing: isManagingHonors,
                            onDelete: {
                                withAnimation {
                                    if let index = myAchievements.firstIndex(
                                        of: item
                                    ) {
                                        myAchievements.remove(at: index)
                                    }
                                }
                            }
                        )
                    }

                    // 添加按钮占位
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.05))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            style: StrokeStyle(
                                                lineWidth: 1,
                                                dash: [4]
                                            )
                                        )
                                        .foregroundStyle(.gray.opacity(0.3))
                                )
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(.gray)
                        }
                        Text("添加")
                            .font(.caption2)
                            .foregroundStyle(.clear)  // 保持对齐占位
                    }
                }
                // 关键修复点：为 ScrollView 的内容添加额外的 padding
                // 这样左上角溢出的删除按钮（offset -4）就不会被切掉了
                .padding(.top, 10)  // 给顶部悬挂的按钮留空间
                .padding(.leading, 10)  // 给左侧悬挂的按钮留空间
                .padding(.bottom, 10)  // 保持平衡
                .padding(.trailing, 16)
            }
        }
        .initialCardStyle(cornerRadius: 20)
    }

    struct AchievementBadge: View {
        let item: AchievementItem
        let isEditing: Bool
        let onDelete: () -> Void

        var body: some View {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {

                    // --- 1. 图标层 (负责抖动) ---
                    ZStack {
                        Circle()
                            .fill(item.color.gradient.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: item.icon)
                            .font(.title)
                            .foregroundStyle(item.color.gradient)
                    }
                    // ⚠️ 关键修复 1：把旋转和它的动画锁在一起，不要影响别人
                    .rotationEffect(.degrees(isEditing ? -3 : 0))
                    // 只有旋转效果使用“无限循环”动画
                    .animation(
                        isEditing
                            ? .easeInOut(duration: 0.15).repeatForever(
                                autoreverses: true
                            ) : .default,
                        value: isEditing
                    )

                    // --- 2. 按钮层 (负责弹出) ---
                    if isEditing {
                        Button(action: onDelete) {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Color.red, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(
                                    color: .black.opacity(0.1),
                                    radius: 2,
                                    x: 0,
                                    y: 1
                                )
                        }
                        .offset(x: -6, y: -6)
                        .zIndex(1)
                        .transition(.scale.combined(with: .opacity))
                        // ⚠️ 关键修复 2：给按钮的出现单独指定一个“非循环”的动画
                        // 这样它只会弹出来一次，不会跟着图标鬼畜
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.6),
                            value: isEditing
                        )
                    }
                }

                Text(item.name)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - 4. Settings Section
    private var settingsSection: some View {
        VStack(spacing: 0) {
            settingRow(icon: "gearshape.fill", title: "通用设置")
            Divider().background(Color.black.opacity(0.05)).padding(
                .leading,
                52
            )
            settingRow(icon: "bell.fill", title: "通知管理")
            Divider().background(Color.black.opacity(0.05)).padding(
                .leading,
                52
            )
            settingRow(icon: "lock.fill", title: "隐私与权限")
        }
        .initialCardStyle(cornerRadius: 16, padding: 0)
    }

    private func settingRow(icon: String, title: String) -> some View {
        Button {
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                        Color.black.opacity(0.05)
                    )
                    Image(systemName: icon).font(.footnote).foregroundStyle(
                        .primary
                    )
                }
                .frame(width: 30, height: 30)
                Text(title).font(.subheadline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(14)
        }
    }

    // MARK: - 5. Sign Out
    private var signOutButton: some View {
        Button {
            Task { await auth.signOut() }
        } label: {
            Text("退出登录").font(.subheadline.bold()).foregroundStyle(.red)
                .frame(maxWidth: .infinity).padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16).stroke(
                        Color.red.opacity(0.2),
                        lineWidth: 1
                    )
                )
        }
    }

    // MARK: - Logic Helpers (逻辑全保留)
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
}

// MARK: - ✅ 视觉回退核心修饰符
struct InitialCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            // ✅ 回退到深邃扩散投影
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
