//
//  CodexWakeupManager.swift
//  VibeCockpit
//
//  In-process scheduler for Codex automatic wakeup.
//

import Combine
import Foundation
import OSLog

@MainActor
final class CodexWakeupManager: ObservableObject {
    static let shared = CodexWakeupManager()

    @Published var settings: CodexWakeupSettings {
        didSet {
            saveSettings()
            configureIntervalAnchorIfNeeded(previous: oldValue)
            tick()
        }
    }
    @Published private(set) var history: [CodexWakeupHistoryItem]
    @Published private(set) var isRunning = false
    @Published private(set) var lastStatusMessage = ""

    private let defaults = UserDefaults.standard
    private let timerManager = TimerManager()
    private let wakeupService = CodexWakeupService()
    private let userSettings = UserSettings.shared

    private var accountStates: [String: CodexWakeupAccountState]
    private var latestUsage: CodexUsageData?
    private var pendingResetTimestampsByAccount: [String: Set<Int>] = [:]
    private var runningAccountIds: Set<UUID> = []
    private var isStarted = false

    private enum DefaultsKey {
        static let settings = "codexWakeupSettings"
        static let accountStates = "codexWakeupAccountStates"
        static let history = "codexWakeupHistory"
    }

    private enum TimerID {
        static let scheduler = "codexWakeupScheduler"
    }

    private init() {
        settings = Self.load(
            CodexWakeupSettings.self,
            key: DefaultsKey.settings,
            from: defaults
        ) ?? CodexWakeupSettings()
        history = Self.load(
            [CodexWakeupHistoryItem].self,
            key: DefaultsKey.history,
            from: defaults
        ) ?? []
        accountStates = Self.load(
            [String: CodexWakeupAccountState].self,
            key: DefaultsKey.accountStates,
            from: defaults
        ) ?? [:]
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        ensureIntervalAnchorForCurrentAccount()
        timerManager.schedule(TimerID.scheduler, interval: 60, repeats: true) { [weak self] in
            Task { @MainActor in
                self?.tick()
            }
        }
        tick()
    }

    func stop() {
        isStarted = false
        timerManager.invalidate(TimerID.scheduler)
    }

    func updateCodexUsage(_ data: CodexUsageData) {
        latestUsage = data
        if let account = userSettings.currentCodexAccount {
            recordPendingResetTimestamps(from: data, for: account)
        }
        tick()
    }

    func clearCodexUsage() {
        latestUsage = nil
    }

    func handleAccountChanged() {
        latestUsage = nil
        CodexAuthService.shared.clearAccessTokenCache()
        ensureIntervalAnchorForCurrentAccount()
        tick()
    }

    func runManualTest() {
        guard let account = userSettings.currentCodexAccount else {
            lastStatusMessage = L.SettingsWakeup.noAccount
            return
        }
        guard !runningAccountIds.contains(account.id) else {
            lastStatusMessage = L.SettingsWakeup.running
            return
        }
        execute(
            CodexWakeupDecision(trigger: .manual),
            account: account,
            usageSnapshot: latestUsage
        )
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func stateForCurrentAccount() -> CodexWakeupAccountState {
        guard let account = userSettings.currentCodexAccount else {
            return CodexWakeupAccountState()
        }
        return accountStates[stateKey(for: account)] ?? CodexWakeupAccountState()
    }

    private func tick() {
        guard let account = userSettings.currentCodexAccount else { return }
        ensureIntervalAnchor(for: account)

        let stateKey = stateKey(for: account)
        let state = accountStates[stateKey] ?? CodexWakeupAccountState()
        let now = Date()
        let pendingResetAt = duePendingResetDate(for: account, state: state, now: now)
        let decision = CodexWakeupScheduler.nextDecision(
            settings: settings,
            state: state,
            now: now,
            primaryResetAt: pendingResetAt ?? latestUsage?.primary?.resetsAt,
            secondaryResetAt: pendingResetAt == nil ? latestUsage?.secondary?.resetsAt : nil,
            isRunning: runningAccountIds.contains(account.id)
        )

        guard let decision else { return }
        execute(decision, account: account, usageSnapshot: latestUsage)
    }

    private func execute(
        _ decision: CodexWakeupDecision,
        account: Account,
        usageSnapshot: CodexUsageData?
    ) {
        guard !runningAccountIds.contains(account.id) else { return }

        runningAccountIds.insert(account.id)
        isRunning = true
        lastStatusMessage = L.SettingsWakeup.running
        Logger.api.notice("Codex wakeup started: \(decision.trigger.rawValue), account=\(account.displayName)")

        wakeupService.runWakeup(account: account) { [weak self] result in
            Task { @MainActor in
                self?.finish(
                    result,
                    decision: decision,
                    account: account,
                    usageSnapshot: usageSnapshot
                )
            }
        }
    }

    private func finish(
        _ result: Result<CodexWakeupRunResult, Error>,
        decision: CodexWakeupDecision,
        account: Account,
        usageSnapshot: CodexUsageData?
    ) {
        runningAccountIds.remove(account.id)
        isRunning = !runningAccountIds.isEmpty

        let key = stateKey(for: account)
        var state = accountStates[key] ?? CodexWakeupAccountState()
        let now = Date()
        let success: Bool
        let durationMs: Int
        let message: String

        switch result {
        case .success(let run):
            success = true
            durationMs = run.durationMs
            message = "OK"
            Logger.api.notice("Codex wakeup succeeded in \(run.durationMs)ms")

        case .failure(let error):
            success = false
            durationMs = 0
            message = error.localizedDescription
            Logger.api.error("Codex wakeup failed: \(error.localizedDescription)")
        }

        let recordedDecision = decisionWithResetKeyIfNeeded(
            decision,
            usageSnapshot: usageSnapshot,
            now: now
        )
        CodexWakeupScheduler.recordCompletion(
            state: &state,
            decision: recordedDecision,
            now: now,
            success: success
        )
        accountStates[key] = state
        prunePendingResetTimestamps(for: key, state: state)
        saveAccountStates()

        appendHistory(CodexWakeupHistoryItem(
            accountId: account.id,
            accountName: account.displayName,
            trigger: decision.trigger,
            timestamp: now,
            success: success,
            durationMs: durationMs,
            message: message
        ))

        lastStatusMessage = success ? L.SettingsWakeup.lastSuccess : message
        if !success, userSettings.notificationsEnabled {
            NotificationManager.shared.sendCodexWakeupFailedNotification(message: message)
        }
        if !success, state.consecutiveFailures >= CodexWakeupScheduler.maxConsecutiveFailures {
            settings.enabled = false
            if userSettings.notificationsEnabled {
                NotificationManager.shared.sendCodexWakeupDisabledNotification()
            }
        }
    }

    private func decisionWithResetKeyIfNeeded(
        _ decision: CodexWakeupDecision,
        usageSnapshot: CodexUsageData?,
        now: Date
    ) -> CodexWakeupDecision {
        guard decision.trigger == .quotaReset, decision.resetKey == nil else {
            return decision
        }

        let resetKeys = [
            usageSnapshot?.primary?.resetsAt,
            usageSnapshot?.secondary?.resetsAt
        ]
        .compactMap { $0 }
        .filter { now.timeIntervalSince($0) >= CodexWakeupScheduler.resetDelaySeconds }
        .map { "quota:\(Int($0.timeIntervalSince1970))" }
        .sorted()

        return CodexWakeupDecision(trigger: decision.trigger, resetKey: resetKeys.first)
    }

    private func configureIntervalAnchorIfNeeded(previous: CodexWakeupSettings) {
        guard settings.enabled, settings.wakeOnInterval else { return }
        let shouldResetAnchor = !previous.enabled
            || !previous.wakeOnInterval
            || previous.intervalHours != settings.intervalHours
        guard shouldResetAnchor, let account = userSettings.currentCodexAccount else { return }
        var state = accountStates[stateKey(for: account)] ?? CodexWakeupAccountState()
        state.intervalAnchorAt = Date()
        state.lastIntervalRunAt = nil
        accountStates[stateKey(for: account)] = state
        saveAccountStates()
    }

    private func ensureIntervalAnchorForCurrentAccount() {
        guard settings.enabled, settings.wakeOnInterval,
              let account = userSettings.currentCodexAccount else { return }
        ensureIntervalAnchor(for: account)
    }

    private func ensureIntervalAnchor(for account: Account) {
        guard settings.enabled, settings.wakeOnInterval else { return }
        let key = stateKey(for: account)
        var state = accountStates[key] ?? CodexWakeupAccountState()
        let before = state
        CodexWakeupScheduler.ensureIntervalAnchor(state: &state, now: Date())
        if state != before {
            accountStates[key] = state
            saveAccountStates()
        }
    }

    private func appendHistory(_ item: CodexWakeupHistoryItem) {
        history.insert(item, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        saveHistory()
    }

    private func stateKey(for account: Account) -> String {
        account.id.uuidString
    }

    private func recordPendingResetTimestamps(from data: CodexUsageData, for account: Account) {
        let timestamps = [
            data.primary?.resetsAt,
            data.secondary?.resetsAt
        ]
        .compactMap { $0 }
        .map { Int($0.timeIntervalSince1970) }

        guard !timestamps.isEmpty else { return }
        let key = stateKey(for: account)
        var existing = pendingResetTimestampsByAccount[key] ?? []
        for timestamp in timestamps {
            existing.insert(timestamp)
        }
        pendingResetTimestampsByAccount[key] = existing
    }

    private func duePendingResetDate(
        for account: Account,
        state: CodexWakeupAccountState,
        now: Date
    ) -> Date? {
        let key = stateKey(for: account)
        return pendingResetTimestampsByAccount[key]?
            .sorted()
            .first { timestamp in
                let resetKey = "quota:\(timestamp)"
                let resetAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
                return !state.completedResetKeys.contains(resetKey)
                    && now.timeIntervalSince(resetAt) >= CodexWakeupScheduler.resetDelaySeconds
            }
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private func prunePendingResetTimestamps(for key: String, state: CodexWakeupAccountState) {
        guard var timestamps = pendingResetTimestampsByAccount[key] else { return }
        timestamps = timestamps.filter { !state.completedResetKeys.contains("quota:\($0)") }
        pendingResetTimestampsByAccount[key] = timestamps
    }

    private func saveSettings() {
        Self.save(settings, key: DefaultsKey.settings, to: defaults)
    }

    private func saveAccountStates() {
        Self.save(accountStates, key: DefaultsKey.accountStates, to: defaults)
    }

    private func saveHistory() {
        Self.save(history, key: DefaultsKey.history, to: defaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
