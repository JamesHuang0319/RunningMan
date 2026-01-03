//
//  AuthView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/23.
//

import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    // MARK: - State
    @State private var email = ""
    @State private var isLoading = false
    @State private var feedbackMessage: String? = nil
    @State private var isError: Bool = false
    
    // 动画状态
    @State private var appearAnimation = false
    @FocusState private var isEmailFocused: Bool

    // 品牌渐变色
    private let brandGradient = LinearGradient(
        colors: [Color(hex: "0F2027"), Color(hex: "203A43"), Color(hex: "2C5364")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // 1. 沉浸式背景
            brandGradient
                .ignoresSafeArea()
                .onTapGesture { isEmailFocused = false } // 点背景收起键盘

            // 背景装饰光斑 (增加氛围感)
            GeometryReader { proxy in
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -50, y: -100)
                
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: proxy.size.width - 150, y: proxy.size.height / 2)
            }
            .ignoresSafeArea()

            // 2. 主内容区
            ScrollView {
                VStack(spacing: 40) {
                    Spacer(minLength: 60)

                    // Hero Logo
                    heroSection
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 20)

                    // 登录卡片
                    loginForm
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 30)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appearAnimation = true
            }
        }
    }

    // MARK: - Subviews

    private var heroSection: some View {
        VStack(spacing: 16) {
            // Logo Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 10)
                
                Image(systemName: "figure.run")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text("RunningMan")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 5)
                
                Text("城市追逐 · 缩圈竞技")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(2)
            }
        }
    }

    private var loginForm: some View {
        VStack(spacing: 24) {
            
            VStack(alignment: .leading, spacing: 8) {
                Text("邮箱登录")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                
                // 输入框容器
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                    
                    TextField("", text: $email, prompt: Text("name@example.com").foregroundColor(.white.opacity(0.3)))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEmailFocused)
                        .foregroundStyle(.white)
                        .tint(.blue) // 光标颜色
                }
                .padding()
                .background(.ultraThinMaterial) // 毛玻璃
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isEmailFocused ? Color.blue.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isEmailFocused)
            }

            // 登录按钮
            Button {
                isEmailFocused = false
                Task { await sendLink() }
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        HStack {
                            Text("发送魔法链接")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
            }
            .disabled(isLoading || email.isEmpty)
            .opacity(email.isEmpty ? 0.6 : 1)
            
            // 反馈信息 (Error / Success)
            if let msg = feedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(msg)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isError ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundStyle(isError ? Color.red.mix(with: .white, by: 0.3) : Color.green.mix(with: .white, by: 0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 底部提示
            Text("未注册邮箱将自动创建新账号")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, -10)
        }
        .padding(24)
        .background(.ultraThinMaterial.opacity(0.6)) // 更通透的背景
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }

    // MARK: - Actions

    private func sendLink() async {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        isLoading = true
        auth.lastError = nil
        // 清除之前的提示
        withAnimation { feedbackMessage = nil }

        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 简单校验
        guard cleaned.contains("@") else {
            isLoading = false
            showFeedback("请输入有效的邮箱地址", isErr: true)
            return
        }

        await auth.signInWithMagicLink(email: cleaned)
        
        isLoading = false

        if let err = auth.lastError {
            showFeedback(err, isErr: true)
        } else {
            showFeedback("登录链接已发送！\n请前往邮箱点击最新邮件。", isErr: false)
        }
    }
    
    private func showFeedback(_ msg: String, isErr: Bool) {
        withAnimation(.spring) {
            self.isError = isErr
            self.feedbackMessage = msg
        }
        
        // 成功消息 5秒后自动消失，失败消息保留
        if !isErr {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { self.feedbackMessage = nil }
            }
        }
    }
}

