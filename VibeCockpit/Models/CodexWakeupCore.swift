import Foundation

public enum CodexWakeupTrigger: String, Codable, Equatable, Sendable {
    case manual
    case quotaReset = "quota_reset"
    case dailyTime = "daily_time"
    case interval
}

public struct CodexWakeupTime: Codable, Equatable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    public static func < (lhs: CodexWakeupTime, rhs: CodexWakeupTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

public struct CodexWakeupSettings: Codable, Equatable, Sendable {
    public static let dailyTimeSlotCount = 3
    public static let defaultDailyTimes = [
        CodexWakeupTime(hour: 6, minute: 0),
        CodexWakeupTime(hour: 11, minute: 0),
        CodexWakeupTime(hour: 16, minute: 0)
    ]

    public var enabled: Bool
    public var wakeOnQuotaReset: Bool
    public var wakeOnDailyTimes: Bool
    public var dailyTimes: [CodexWakeupTime]
    public var wakeOnInterval: Bool
    public var intervalHours: Int

    public init(
        enabled: Bool = false,
        wakeOnQuotaReset: Bool = true,
        wakeOnDailyTimes: Bool = true,
        dailyTimes: [CodexWakeupTime] = CodexWakeupSettings.defaultDailyTimes,
        wakeOnInterval: Bool = false,
        intervalHours: Int = 4
    ) {
        self.enabled = enabled
        self.wakeOnQuotaReset = wakeOnQuotaReset
        self.wakeOnDailyTimes = wakeOnDailyTimes
        self.dailyTimes = Self.normalizedDailyTimes(dailyTimes)
        self.wakeOnInterval = wakeOnInterval
        self.intervalHours = Self.normalizedIntervalHours(intervalHours)
    }

    public static func normalizedIntervalHours(_ value: Int) -> Int {
        min(24, max(1, value))
    }

    public static func normalizedDailyTimes(_ value: [CodexWakeupTime]) -> [CodexWakeupTime] {
        var times = Array(value.prefix(dailyTimeSlotCount))
        while times.count < dailyTimeSlotCount {
            times.append(defaultDailyTimes[times.count])
        }
        return times
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case wakeOnQuotaReset
        case wakeOnDailyTimes
        case dailyTimes
        case wakeOnInterval
        case intervalHours
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            wakeOnQuotaReset: try container.decodeIfPresent(Bool.self, forKey: .wakeOnQuotaReset) ?? true,
            wakeOnDailyTimes: try container.decodeIfPresent(Bool.self, forKey: .wakeOnDailyTimes) ?? true,
            dailyTimes: try container.decodeIfPresent([CodexWakeupTime].self, forKey: .dailyTimes) ?? Self.defaultDailyTimes,
            wakeOnInterval: try container.decodeIfPresent(Bool.self, forKey: .wakeOnInterval) ?? false,
            intervalHours: try container.decodeIfPresent(Int.self, forKey: .intervalHours) ?? 4
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(wakeOnQuotaReset, forKey: .wakeOnQuotaReset)
        try container.encode(wakeOnDailyTimes, forKey: .wakeOnDailyTimes)
        try container.encode(Self.normalizedDailyTimes(dailyTimes), forKey: .dailyTimes)
        try container.encode(wakeOnInterval, forKey: .wakeOnInterval)
        try container.encode(intervalHours, forKey: .intervalHours)
    }
}

public struct CodexWakeupAccountState: Codable, Equatable, Sendable {
    public var lastRunAt: Date?
    public var lastAutomaticRunAt: Date?
    public var lastIntervalRunAt: Date?
    public var intervalAnchorAt: Date?
    public var completedResetKeys: Set<String>
    public var completedDailyTimeKeys: Set<String>
    public var dailyRunDay: Int?
    public var dailyRunCount: Int
    public var consecutiveFailures: Int

    public init(
        lastRunAt: Date? = nil,
        lastAutomaticRunAt: Date? = nil,
        lastIntervalRunAt: Date? = nil,
        intervalAnchorAt: Date? = nil,
        completedResetKeys: Set<String> = [],
        completedDailyTimeKeys: Set<String> = [],
        dailyRunDay: Int? = nil,
        dailyRunCount: Int = 0,
        consecutiveFailures: Int = 0
    ) {
        self.lastRunAt = lastRunAt
        self.lastAutomaticRunAt = lastAutomaticRunAt
        self.lastIntervalRunAt = lastIntervalRunAt
        self.intervalAnchorAt = intervalAnchorAt
        self.completedResetKeys = completedResetKeys
        self.completedDailyTimeKeys = completedDailyTimeKeys
        self.dailyRunDay = dailyRunDay
        self.dailyRunCount = dailyRunCount
        self.consecutiveFailures = consecutiveFailures
    }

    private enum CodingKeys: String, CodingKey {
        case lastRunAt
        case lastAutomaticRunAt
        case lastIntervalRunAt
        case intervalAnchorAt
        case completedResetKeys
        case completedDailyTimeKeys
        case dailyRunDay
        case dailyRunCount
        case consecutiveFailures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lastRunAt: try container.decodeIfPresent(Date.self, forKey: .lastRunAt),
            lastAutomaticRunAt: try container.decodeIfPresent(Date.self, forKey: .lastAutomaticRunAt),
            lastIntervalRunAt: try container.decodeIfPresent(Date.self, forKey: .lastIntervalRunAt),
            intervalAnchorAt: try container.decodeIfPresent(Date.self, forKey: .intervalAnchorAt),
            completedResetKeys: try container.decodeIfPresent(Set<String>.self, forKey: .completedResetKeys) ?? [],
            completedDailyTimeKeys: try container.decodeIfPresent(Set<String>.self, forKey: .completedDailyTimeKeys) ?? [],
            dailyRunDay: try container.decodeIfPresent(Int.self, forKey: .dailyRunDay),
            dailyRunCount: try container.decodeIfPresent(Int.self, forKey: .dailyRunCount) ?? 0,
            consecutiveFailures: try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastRunAt, forKey: .lastRunAt)
        try container.encodeIfPresent(lastAutomaticRunAt, forKey: .lastAutomaticRunAt)
        try container.encodeIfPresent(lastIntervalRunAt, forKey: .lastIntervalRunAt)
        try container.encodeIfPresent(intervalAnchorAt, forKey: .intervalAnchorAt)
        try container.encode(completedResetKeys, forKey: .completedResetKeys)
        try container.encode(completedDailyTimeKeys, forKey: .completedDailyTimeKeys)
        try container.encodeIfPresent(dailyRunDay, forKey: .dailyRunDay)
        try container.encode(dailyRunCount, forKey: .dailyRunCount)
        try container.encode(consecutiveFailures, forKey: .consecutiveFailures)
    }
}

public struct CodexWakeupDecision: Equatable, Sendable {
    public let trigger: CodexWakeupTrigger
    public let resetKey: String?
    public let dailyTimeKey: String?

    public init(trigger: CodexWakeupTrigger, resetKey: String? = nil, dailyTimeKey: String? = nil) {
        self.trigger = trigger
        self.resetKey = resetKey
        self.dailyTimeKey = dailyTimeKey
    }
}

public struct CodexWakeupHistoryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let accountId: UUID?
    public let accountName: String
    public let trigger: CodexWakeupTrigger
    public let timestamp: Date
    public let success: Bool
    public let durationMs: Int
    public let message: String

    public init(
        id: UUID = UUID(),
        accountId: UUID?,
        accountName: String,
        trigger: CodexWakeupTrigger,
        timestamp: Date,
        success: Bool,
        durationMs: Int,
        message: String
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.trigger = trigger
        self.timestamp = timestamp
        self.success = success
        self.durationMs = durationMs
        self.message = message
    }
}

public enum CodexWakeupScheduler {
    public static let cooldownSeconds: TimeInterval = 30 * 60
    public static let resetDelaySeconds: TimeInterval = 10
    public static let dailyTimeWindowSeconds: TimeInterval = 15 * 60
    public static let maxDailyRuns = 8
    public static let maxConsecutiveFailures = 3

    public static func ensureIntervalAnchor(state: inout CodexWakeupAccountState, now: Date) {
        if state.intervalAnchorAt == nil {
            state.intervalAnchorAt = now
        }
    }

    public static func nextDecision(
        settings: CodexWakeupSettings,
        state: CodexWakeupAccountState,
        now: Date,
        primaryResetAt: Date?,
        secondaryResetAt: Date?,
        isRunning: Bool,
        calendar: Calendar = .current
    ) -> CodexWakeupDecision? {
        guard settings.enabled, !isRunning else { return nil }

        if settings.wakeOnDailyTimes,
           let key = dueDailyTimeKey(
            settings: settings,
            now: now,
            completedDailyTimeKeys: state.completedDailyTimeKeys,
            calendar: calendar
           ) {
            return CodexWakeupDecision(trigger: .dailyTime, dailyTimeKey: key)
        }

        guard state.consecutiveFailures < maxConsecutiveFailures else { return nil }
        guard dailyCount(state, now: now, calendar: calendar) < maxDailyRuns else { return nil }
        if let lastAutomaticRunAt = state.lastAutomaticRunAt,
           now.timeIntervalSince(lastAutomaticRunAt) < cooldownSeconds {
            return nil
        }

        if settings.wakeOnQuotaReset,
           let key = dueResetKey(
            now: now,
            primaryResetAt: primaryResetAt,
            secondaryResetAt: secondaryResetAt,
            completedResetKeys: state.completedResetKeys
           ) {
            return CodexWakeupDecision(trigger: .quotaReset, resetKey: key)
        }

        if settings.wakeOnInterval,
           let anchor = state.lastIntervalRunAt ?? state.intervalAnchorAt {
            let interval = TimeInterval(CodexWakeupSettings.normalizedIntervalHours(settings.intervalHours) * 3600)
            if now.timeIntervalSince(anchor) >= interval {
                return CodexWakeupDecision(trigger: .interval)
            }
        }

        return nil
    }

    public static func recordCompletion(
        state: inout CodexWakeupAccountState,
        decision: CodexWakeupDecision,
        now: Date,
        success: Bool,
        calendar: Calendar = .current
    ) {
        state.lastRunAt = now
        if decision.trigger != .manual {
            state.lastAutomaticRunAt = now
        }
        if decision.trigger == .interval {
            state.lastIntervalRunAt = now
        }
        if let resetKey = decision.resetKey {
            state.completedResetKeys.insert(resetKey)
        }
        if let dailyTimeKey = decision.dailyTimeKey {
            state.completedDailyTimeKeys.insert(dailyTimeKey)
        }
        let day = dayIndex(now, calendar: calendar)
        if state.dailyRunDay == day {
            state.dailyRunCount += 1
        } else {
            state.dailyRunDay = day
            state.dailyRunCount = 1
        }
        state.consecutiveFailures = success ? 0 : state.consecutiveFailures + 1
    }

    private static func dueResetKey(
        now: Date,
        primaryResetAt: Date?,
        secondaryResetAt: Date?,
        completedResetKeys: Set<String>
    ) -> String? {
        [primaryResetAt, secondaryResetAt]
            .compactMap { $0 }
            .filter { now.timeIntervalSince($0) >= resetDelaySeconds }
            .map { Int($0.timeIntervalSince1970) }
            .sorted()
            .map { "quota:\($0)" }
            .first { !completedResetKeys.contains($0) }
    }

    private static func dueDailyTimeKey(
        settings: CodexWakeupSettings,
        now: Date,
        completedDailyTimeKeys: Set<String>,
        calendar: Calendar
    ) -> String? {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        guard let currentHour = components.hour,
              let currentMinute = components.minute else {
            return nil
        }

        return CodexWakeupSettings.normalizedDailyTimes(settings.dailyTimes)
            .sorted()
            .compactMap { time -> String? in
                guard time.hour == currentHour, time.minute == currentMinute else {
                    return nil
                }
                let key = dailyTimeKey(for: time, dateComponents: components)
                return completedDailyTimeKeys.contains(key) ? nil : key
            }
            .first
    }

    private static func dailyTimeKey(
        for time: CodexWakeupTime,
        dateComponents components: DateComponents
    ) -> String {
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "daily:%04d-%02d-%02d:%02d:%02d", year, month, day, time.hour, time.minute)
    }

    private static func dailyCount(_ state: CodexWakeupAccountState, now: Date, calendar: Calendar) -> Int {
        state.dailyRunDay == dayIndex(now, calendar: calendar) ? state.dailyRunCount : 0
    }

    private static func dayIndex(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return Int(floor(date.timeIntervalSince1970 / 86_400))
        }
        return year * 10_000 + month * 100 + day
    }
}

public struct CodexWakeupRequestBody: Codable, Equatable, Sendable {
    public var model: String
    public var input: [CodexWakeupInputMessage]
    public var instructions: String
    public var reasoning: CodexWakeupReasoning
    public var include: [String]
    public var parallelToolCalls: Bool
    public var store: Bool
    public var stream: Bool

    public init(
        model: String,
        input: [CodexWakeupInputMessage],
        instructions: String,
        reasoning: CodexWakeupReasoning,
        include: [String],
        parallelToolCalls: Bool,
        store: Bool,
        stream: Bool
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.reasoning = reasoning
        self.include = include
        self.parallelToolCalls = parallelToolCalls
        self.store = store
        self.stream = stream
    }

    public static func officialWakeup(
        prompt: String = "请回复 OK",
        model: String = "gpt-5.4",
        reasoningEffort: String = "medium"
    ) -> CodexWakeupRequestBody {
        CodexWakeupRequestBody(
            model: model,
            input: [
                CodexWakeupInputMessage(
                    type: "message",
                    role: "user",
                    content: [
                        CodexWakeupInputContent(type: "input_text", text: prompt)
                    ]
                )
            ],
            instructions: "",
            reasoning: CodexWakeupReasoning(effort: reasoningEffort, summary: "auto"),
            include: ["reasoning.encrypted_content"],
            parallelToolCalls: true,
            store: false,
            stream: true
        )
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case reasoning
        case include
        case parallelToolCalls = "parallel_tool_calls"
        case store
        case stream
    }
}

public struct CodexWakeupInputMessage: Codable, Equatable, Sendable {
    public var type: String
    public var role: String
    public var content: [CodexWakeupInputContent]

    public init(type: String, role: String, content: [CodexWakeupInputContent]) {
        self.type = type
        self.role = role
        self.content = content
    }
}

public struct CodexWakeupInputContent: Codable, Equatable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct CodexWakeupReasoning: Codable, Equatable, Sendable {
    public var effort: String
    public var summary: String

    public init(effort: String, summary: String) {
        self.effort = effort
        self.summary = summary
    }
}

public enum CodexWakeupResponseParser {
    public static func replyText(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        let fragments = ssePayloads(from: text)
        if !fragments.isEmpty {
            return fragments
                .compactMap { jsonObject(from: Data($0.utf8)) }
                .flatMap(extractTexts)
                .joined(separator: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let object = jsonObject(from: data) else { return "" }
        return extractTexts(from: object)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isSuccessfulWakeupReply(_ reply: String) -> Bool {
        reply.range(of: "OK", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func ssePayloads(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("data:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "[DONE]" }
    }

    private static func jsonObject(from data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    private static func extractTexts(from object: Any) -> [String] {
        if let dictionary = object as? [String: Any] {
            if let response = dictionary["response"] {
                return extractTexts(from: response)
            }
            if let output = dictionary["output"] {
                return extractTexts(from: output)
            }
            if dictionary["type"] as? String == "output_text",
               let text = dictionary["text"] as? String {
                return [text]
            }
            if dictionary["type"] as? String == "response.output_text.delta",
               let delta = dictionary["delta"] as? String {
                return [delta]
            }
            return dictionary.values.flatMap(extractTexts)
        }
        if let array = object as? [Any] {
            return array.flatMap(extractTexts)
        }
        return []
    }
}
