//
//  ProfileView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ProfileStore.self) private var profileStore

    @State private var pickedItem: PhotosPickerItem?
    @State private var localPreview: Image?
    @State private var isSavingAvatar = false

    @State private var showPicker = false

    // 用户名编辑
    @State private var isEditingName = false
    @State private var editingName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var isSavingName = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard

                    if let err = profileStore.error, !err.isEmpty {
                        errorCard(err)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if auth.userId != nil {
                        Button("退出") {
                            Task { await auth.signOut() }
                        }
                    }
                }
            }
            .refreshable {
                guard let uid = auth.userId else { return }
                await profileStore.loadMe(
                    userId: uid,
                    forceRefreshAvatar: true,
                    clearImageCacheIfForce: false,
                    usePersistedFirst: false
                )
            }
            .task {
                // 兜底：一般 RootView 已 bootstrap
                guard let uid = auth.userId else { return }
                if profileStore.me?.id != uid {
                    await profileStore.loadMe(userId: uid, usePersistedFirst: true)
                }
                // 准备用户名编辑初值
                if editingName.isEmpty {
                    editingName = profileStore.me?.username ?? defaultName(for: uid)
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePickedAvatar(newItem) }
            }
        }
    }

    // MARK: - UI

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(alignment: .center, spacing: 14) {
                // ✅ 头像更大：88
                AvatarView(
                    size: 88,
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
                .overlay(alignment: .bottomTrailing) {
                    // ✅ 只有“没上传过头像”才显示相机 icon
                    if auth.userId != nil, shouldShowCameraBadge {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.6), in: Circle())
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    // ✅ 用户名：展示/编辑两种状态
                    if auth.userId == nil {
                        Text("Not signed in")
                            .font(.title3.bold())
                    } else if isEditingName {
                        HStack(spacing: 8) {
                            TextField("用户名", text: $editingName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($nameFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { Task { await saveName() } }

                            if isSavingName {
                                ProgressView().scaleEffect(0.9)
                            } else {
                                Button {
                                    Task { await saveName() }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Button {
                            guard auth.userId != nil else { return }
                            isEditingName = true
                            nameFieldFocused = true
                            if let uid = auth.userId {
                                editingName = profileStore.me?.username ?? defaultName(for: uid)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(displayName)
                                    .font(.title3.bold())
                                Image(systemName: "pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Text(displaySubline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if isSavingAvatar {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.9)
                            Text("上传头像中…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }

            Divider().opacity(0.4)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.black.opacity(0.06), lineWidth: 1)
        )
        .onChange(of: isEditingName) { _, newValue in
            // 退出编辑时收起键盘
            if !newValue { nameFieldFocused = false }
        }
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.red)

            Spacer()
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Computed

    private var currentAvatarPath: String? {
        guard let me = profileStore.me else { return nil }
        return profileStore.avatarPath(for: me)
    }

    private var currentSignedURL: URL? {
        guard let path = currentAvatarPath else { return nil }
        return profileStore.signedURL(forPath: path)
    }

    /// ✅ 只有在用户从未上传过头像时才显示相机 badge
    /// 规则：me.avatarURL == nil 认为没上传过
    private var shouldShowCameraBadge: Bool {
        profileStore.me?.avatarURL == nil && localPreview == nil
    }

    private var displayName: String {
        guard let uid = auth.userId else { return "Not signed in" }
        if let name = profileStore.me?.username, !name.isEmpty { return name }
        return defaultName(for: uid)
    }

    private func defaultName(for uid: UUID) -> String {
        "Player\(uid.uuidString.prefix(4))"
    }

    private var displaySubline: String {
        // 如果你 AuthStore 有 email，就改成 auth.email ?? shortUID
        guard let uid = auth.userId else { return "Sign in to continue" }
        return String(uid.uuidString.prefix(8)).uppercased()
    }

    // MARK: - Actions

    private func handlePickedAvatar(_ item: PhotosPickerItem) async {
        guard let uid = auth.userId else { return }

        isSavingAvatar = true
        defer { isSavingAvatar = false }

        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: raw),
                  let jpeg = img.jpegData(compressionQuality: 0.85) else {
                return
            }

            // 先展示本地预览（更丝滑）
            await MainActor.run {
                localPreview = Image(uiImage: img)
            }

            // 自动上传 + 更新 DB + 刷新 signed URL
            await profileStore.updateMyAvatar(userId: uid, jpegData: jpeg)

            // 上传成功：清本地预览，让远端接管
            await MainActor.run {
                localPreview = nil
                pickedItem = nil
            }
        } catch {
            await MainActor.run { pickedItem = nil }
        }
    }

    private func saveName() async {
        guard let uid = auth.userId else { return }
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        isSavingName = true
        defer { isSavingName = false }

        await profileStore.updateMyUsername(userId: uid, username: newName)

        // 结束编辑
        await MainActor.run {
            isEditingName = false
            nameFieldFocused = false
        }
    }
}
