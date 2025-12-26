//
//  DebugLog.swift
//  RunningMan
//
//  Created by 黄名靖 on 2025/12/24.
//

import Foundation
import os

enum DLog {
    static var enabled = true
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "DLog")

    static func info(_ msg: String) {
        guard enabled else { return }
        logger.info("ℹ️ \(msg, privacy: .public)")
    }

    static func ok(_ msg: String) {
        guard enabled else { return }
        logger.notice("✅ \(msg, privacy: .public)")
    }

    static func warn(_ msg: String) {
        guard enabled else { return }
        logger.warning("⚠️ \(msg, privacy: .public)")
    }

    static func err(_ msg: String) {
        guard enabled else { return }
        logger.error("❌ \(msg, privacy: .public)")
    }
}
