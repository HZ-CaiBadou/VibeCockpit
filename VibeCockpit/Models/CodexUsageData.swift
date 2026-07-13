//
//  CodexUsageData.swift
//  VibeCockpit
//
//  Created by f-is-h on 2026-04-24.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - 内部数据模型

/// Codex 使用量数据（应用内部使用的标准化结构）
struct CodexUsageData: Sendable {
    /// API 返回的 primary 配额窗口。窗口长度由 `windowSeconds` 决定，不假设为 5 小时。
    let primary: LimitData?
    /// API 返回的 secondary 配额窗口。窗口长度由 `windowSeconds` 决定，不假设为 7 天。
    let secondary: LimitData?
    /// Codex Extra Usage / credits 数据
    let extraUsage: CodexExtraUsageData?

    struct LimitData: Sendable {
        /// 当前使用百分比 (0-100)
        let percentage: Double
        /// 重置时间，nil 表示尚未开始使用
        let resetsAt: Date?
        /// API 返回的实际窗口时长；缺失时仅展示为通用窗口，不伪造 5 小时标签。
        let windowSeconds: Int?

        init(percentage: Double, resetsAt: Date?, windowSeconds: Int? = nil) {
            self.percentage = percentage
            self.resetsAt = resetsAt
            self.windowSeconds = windowSeconds
        }

        /// 紧凑的真实窗口标签，例如 `7d`、`5h`。接口未提供时返回 nil，交由 UI 使用通用名称。
        var compactWindowLabel: String? {
            guard let windowSeconds, windowSeconds > 0 else { return nil }
            let minutes = max(1, Int((Double(windowSeconds) / 60).rounded(.up)))
            if minutes % (24 * 60) == 0 {
                return "\(minutes / (24 * 60))d"
            }
            if minutes % 60 == 0 {
                return "\(minutes / 60)h"
            }
            return "\(minutes)m"
        }
    }
}

// MARK: - API 响应模型

/// Codex /backend-api/wham/usage 响应模型
nonisolated struct CodexUsageResponse: Decodable, Sendable {
    let account_id: String?
    let email: String?
    let plan_type: String?
    let rate_limit: RateLimit?
    let credits: Credits?
    let spend_control: SpendControl?

    struct RateLimit: Decodable, Sendable {
        let allowed: Bool?
        let limit_reached: Bool?
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Window: Decodable, Sendable {
        /// 使用百分比 (0-100)
        let used_percent: Double
        /// 窗口时长（秒）：18000 = 5小时，604800 = 7天
        let limit_window_seconds: Int?
        /// 距重置剩余秒数
        let reset_after_seconds: Int?
        /// 重置时间（Unix 时间戳，与 Claude 的 ISO 8601 不同）
        let reset_at: Int?

        private enum CodingKeys: String, CodingKey {
            case used_percent
            case limit_window_seconds
            case reset_after_seconds
            case reset_at
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // OpenAI 的未公开接口偶尔会返回整数、浮点数或 null。单个窗口字段异常时，
            // 不应导致整份用量响应解码失败。
            used_percent = container.decodeLossyDouble(forKey: .used_percent) ?? 0
            limit_window_seconds = container.decodeLossyInt(forKey: .limit_window_seconds)
            reset_after_seconds = container.decodeLossyInt(forKey: .reset_after_seconds)
            reset_at = container.decodeLossyInt(forKey: .reset_at)
        }
    }

    struct Credits: Decodable, Sendable {
        let has_credits: Bool?
        let unlimited: Bool?
        let overage_limit_reached: Bool?
        let balance: String?
        let approx_local_messages: [Int]?
        let approx_cloud_messages: [Int]?

        private enum CodingKeys: String, CodingKey {
            case has_credits
            case unlimited
            case overage_limit_reached
            case balance
            case approx_local_messages
            case approx_cloud_messages
        }

        init(
            has_credits: Bool?,
            unlimited: Bool?,
            overage_limit_reached: Bool?,
            balance: String?,
            approx_local_messages: [Int]?,
            approx_cloud_messages: [Int]?
        ) {
            self.has_credits = has_credits
            self.unlimited = unlimited
            self.overage_limit_reached = overage_limit_reached
            self.balance = balance
            self.approx_local_messages = approx_local_messages
            self.approx_cloud_messages = approx_cloud_messages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            has_credits = try container.decodeIfPresent(Bool.self, forKey: .has_credits)
            unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)
            overage_limit_reached = try container.decodeIfPresent(Bool.self, forKey: .overage_limit_reached)
            approx_local_messages = try container.decodeIfPresent([Int].self, forKey: .approx_local_messages)
            approx_cloud_messages = try container.decodeIfPresent([Int].self, forKey: .approx_cloud_messages)

            if let stringBalance = try? container.decodeIfPresent(String.self, forKey: .balance) {
                balance = stringBalance
            } else if let doubleBalance = try? container.decodeIfPresent(Double.self, forKey: .balance) {
                balance = String(doubleBalance)
            } else if let intBalance = try? container.decodeIfPresent(Int.self, forKey: .balance) {
                balance = String(intBalance)
            } else {
                balance = nil
            }
        }
    }

    struct SpendControl: Decodable, Sendable {
        let reached: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case account_id
        case email
        case plan_type
        case rate_limit
        case credits
        case spend_control
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 统计字段与付费 credits 独立于配额窗口；其中任一字段变更不应让基础用量消失。
        func decodeLenient<T: Decodable>(_ type: T.Type, forKey key: CodingKeys) -> T? {
            try? container.decodeIfPresent(T.self, forKey: key)
        }

        account_id = decodeLenient(String.self, forKey: .account_id)
        email = decodeLenient(String.self, forKey: .email)
        plan_type = decodeLenient(String.self, forKey: .plan_type)
        rate_limit = decodeLenient(RateLimit.self, forKey: .rate_limit)
        credits = decodeLenient(Credits.self, forKey: .credits)
        spend_control = decodeLenient(SpendControl.self, forKey: .spend_control)
    }

    /// 将 API 响应转换为内部 CodexUsageData
    func toCodexUsageData() -> CodexUsageData {
        let now = Date()

        func resolvedResetDate(for window: Window) -> Date? {
            if let resetAt = window.reset_at, resetAt > 0 {
                return Date(timeIntervalSince1970: TimeInterval(resetAt))
            }
            if let resetAfterSeconds = window.reset_after_seconds, resetAfterSeconds >= 0 {
                return now.addingTimeInterval(TimeInterval(resetAfterSeconds))
            }
            return nil
        }

        let primary: CodexUsageData.LimitData? = {
            guard let w = rate_limit?.primary_window else { return nil }
            let resetsAt = resolvedResetDate(for: w)
            return .init(
                percentage: w.used_percent.clamped(to: 0...100),
                resetsAt: resetsAt,
                windowSeconds: w.limit_window_seconds
            )
        }()

        let secondary: CodexUsageData.LimitData? = {
            guard let w = rate_limit?.secondary_window else { return nil }
            let resetsAt = resolvedResetDate(for: w)
            return .init(
                percentage: w.used_percent.clamped(to: 0...100),
                resetsAt: resetsAt,
                windowSeconds: w.limit_window_seconds
            )
        }()

        let extraUsage = credits.map {
            CodexExtraUsageData(
                hasCredits: $0.has_credits ?? false,
                unlimited: $0.unlimited ?? false,
                overageLimitReached: $0.overage_limit_reached ?? false,
                spendControlReached: spend_control?.reached ?? false,
                balance: CodexExtraUsageData.parseBalance($0.balance),
                approxLocalMessages: $0.approx_local_messages,
                approxCloudMessages: $0.approx_cloud_messages
            )
        }

        return CodexUsageData(primary: primary, secondary: secondary, extraUsage: extraUsage)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Codex Extra Usage / credits 数据
/// Codex 返回的是可用余额和大致可发送消息数，而不是 Claude Extra Usage 的 used/limit 格式。
nonisolated struct CodexExtraUsageData: Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let overageLimitReached: Bool
    let spendControlReached: Bool
    let balance: Decimal?
    let approxLocalMessages: [Int]?
    let approxCloudMessages: [Int]?
    let visualPercentage: Double?

    init(
        hasCredits: Bool,
        unlimited: Bool,
        overageLimitReached: Bool,
        spendControlReached: Bool,
        balance: Decimal?,
        approxLocalMessages: [Int]?,
        approxCloudMessages: [Int]?,
        visualPercentage: Double? = nil
    ) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.overageLimitReached = overageLimitReached
        self.spendControlReached = spendControlReached
        self.balance = balance
        self.approxLocalMessages = approxLocalMessages
        self.approxCloudMessages = approxCloudMessages
        self.visualPercentage = visualPercentage
    }

    var enabled: Bool {
        if hasCredits || unlimited || overageLimitReached || spendControlReached {
            return true
        }
        return (balanceValue ?? 0) > 0
    }

    var percentage: Double? {
        if let visualPercentage {
            return visualPercentage
        }
        if overageLimitReached || spendControlReached {
            return 100
        }
        if hasCredits || unlimited || (balanceValue ?? 0) > 0 {
            return 0
        }
        return nil
    }

    var balanceValue: Double? {
        guard let balance else { return nil }
        return NSDecimalNumber(decimal: balance).doubleValue
    }

    static func parseBalance(_ value: String?) -> Decimal? {
        guard let value, !value.isEmpty else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - 格式化桥接

extension CodexUsageData.LimitData {
    /// 转换为 UsageData.LimitData，复用其全部格式化方法（倒计时、重置时间等）
    func asUsageLimitData() -> UsageData.LimitData {
        return UsageData.LimitData(percentage: percentage, resetsAt: resetsAt)
    }
}

// MARK: - Session 响应模型

/// Codex /api/auth/session 响应模型
/// 用于获取 Bearer accessToken
nonisolated struct CodexSessionResponse: Codable, Sendable {
    let accessToken: String?
    let user: User?

    struct User: Codable, Sendable {
        let name: String?
        let email: String?
    }
}
