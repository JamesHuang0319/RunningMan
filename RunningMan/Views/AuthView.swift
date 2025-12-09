//
//  AuthView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    @State private var email = ""
    @State private var isLoading = false
    @State private var info: String? = nil

    @FocusState private var isEmailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("邮箱登录")
                            .font(.headline)

                        TextField("name@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .focused($isEmailFocused)
                            .padding(12)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            isEmailFocused = false      // ✅ 收键盘
                            Task { await sendLink() }
                        } label: {
                            HStack {
                                Spacer()
                                if isLoading { ProgressView().tint(.white) }
                                Text(isLoading ? "发送中..." : "发送登录链接")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let info {
                            Text(info)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }

                        if let err = auth.lastError {
                            Text("错误：\(err)")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                }

                debugCard

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onTapGesture { isEmailFocused = false } // ✅ 点空白收键盘
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 52))
            Text("登录 RunningMan")
                .font(.largeTitle).bold()
            Text("多人追逐 · 安全圈缩小 · 找到你身边的“猎人”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var debugCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug")
                    .font(.headline)

                row("isAuthenticated", auth.isAuthenticated ? "true" : "false")
                row("userId", auth.userId?.uuidString ?? "nil")
                row("lastEvent", auth.lastAuthEvent ?? "nil")
                row("lastCallbackURL", auth.lastCallbackURL ?? "nil")
                if let err = auth.lastError {
                    row("lastError", err)
                }

                Text("提示：退出后再次登录，请务必使用“最新一封邮件”的链接（旧链接一定会过期/已被消费）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(v).font(.caption).textSelection(.enabled)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 6, y: 2)
    }

    private func sendLink() async {
        isLoading = true
        defer { isLoading = false }

        info = nil
        auth.lastError = nil // ✅ 发送前清旧错误（关键）

        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines)
        await auth.signInWithMagicLink(email: cleaned)

        if auth.lastError == nil {
            info = "已发送，请去邮箱点“最新”的那封邮件完成登录。"
        }
    }
}

