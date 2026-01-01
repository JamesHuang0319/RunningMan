//
//  AvatarView.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/25.
//

import SwiftUI
import Kingfisher

struct AvatarView: View {
    enum ShapeStyle {
        case circle
        case rounded(CGFloat)
    }

    let size: CGFloat
    let shape: ShapeStyle

    let placeholderSystemName: String
    let localPreview: Image?
    let path: String?
    let signedURL: URL?
    let onTap: (() -> Void)?

    var body: some View {
        Group {
            switch shape {
            case .circle:
                content
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))

            case .rounded(let r):
                content
                    .clipShape(RoundedRectangle(cornerRadius: r))
                    .contentShape(RoundedRectangle(cornerRadius: r))
                    .overlay(RoundedRectangle(cornerRadius: r).stroke(.black.opacity(0.06), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .onTapGesture { onTap?() }
        .accessibilityLabel("Avatar")
    }

    private var content: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.black.opacity(0.06))

            if let localPreview {
                localPreview
                    .resizable()
                    .scaledToFill()

            } else if let path, let signedURL {
                // ✅ 显式用 Kingfisher 的 ImageResource，避免你工程里同名类型冲突/弃用提示
                let resource = KF.ImageResource(downloadURL: signedURL, cacheKey: path)

                KFImage(source: .network(resource))
                    .placeholder { ProgressView() }
                    .loadDiskFileSynchronously()
                    .fade(duration: 0.15)
                    .resizable()
                    .scaledToFill()

            } else {
                Image(systemName: placeholderSystemName)
                    .font(.system(size: size * 0.34, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
