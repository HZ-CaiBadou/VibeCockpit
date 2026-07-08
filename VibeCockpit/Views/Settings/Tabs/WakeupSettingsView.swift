//
//  WakeupSettingsView.swift
//  VibeCockpit
//
//  Settings tab for Codex automatic wakeup.
//

import SwiftUI

struct WakeupSettingsView: View {
    @ObservedObject private var wakeupManager = CodexWakeupManager.shared
    @ObservedObject private var userSettings = UserSettings.shared

    private var currentAccount: Account? {
        userSettings.currentCodexAccount
    }

    private var isOAuthAccount: Bool {
        guard let account = currentAccount else { return false }
        return CodexAuthService.isOAuthRefreshToken(account.sessionKey)
    }

    private var canRunWakeup: Bool {
        currentAccount != nil && isOAuthAccount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                configurationCard
                statusCard
                historyCard
            }
            .padding()
        }
    }

    private var configurationCard: some View {
        SettingCard(
            icon: "alarm",
            iconColor: .orange,
            title: L.SettingsWakeup.section,
            hint: L.SettingsWakeup.hint
        ) {
            VStack(alignment: .leading, spacing: 14) {
                accountRow

                if !canRunWakeup {
                    warningRow(text: currentAccount == nil ? L.SettingsWakeup.noAccount : L.SettingsWakeup.oauthRequired)
                }

                Divider()

                Toggle(isOn: binding(\.enabled)) {
                    Text(L.SettingsWakeup.enable)
                }
                .toggleStyle(.checkbox)
                .disabled(!canRunWakeup)

                Toggle(isOn: binding(\.wakeOnQuotaReset)) {
                    Text(L.SettingsWakeup.quotaReset)
                }
                .toggleStyle(.checkbox)
                .disabled(!canRunWakeup || !wakeupManager.settings.enabled)

                Toggle(isOn: binding(\.wakeOnDailyTimes)) {
                    Text(L.SettingsWakeup.dailyTimes)
                }
                .toggleStyle(.checkbox)
                .disabled(!canRunWakeup || !wakeupManager.settings.enabled)

                VStack(spacing: 8) {
                    ForEach(0..<CodexWakeupSettings.dailyTimeSlotCount, id: \.self) { index in
                        dailyTimeRow(index)
                    }
                }
                .disabled(!canRunWakeup || !wakeupManager.settings.enabled || !wakeupManager.settings.wakeOnDailyTimes)

                Divider()

                HStack {
                    Button(action: { wakeupManager.runManualTest() }) {
                        Label(L.SettingsWakeup.testNow, systemImage: "bolt.fill")
                    }
                    .disabled(!canRunWakeup || wakeupManager.isRunning)

                    if wakeupManager.isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        let state = wakeupManager.stateForCurrentAccount()

        return SettingCard(
            icon: "waveform.path.ecg",
            iconColor: .green,
            title: L.SettingsWakeup.recentStatus,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 10) {
                infoRow(title: L.SettingsWakeup.recentStatus, value: statusText)
                infoRow(title: L.SettingsWakeup.lastRun, value: formattedDate(state.lastRunAt) ?? L.SettingsWakeup.neverRun)
                infoRow(title: L.SettingsWakeup.today, value: "\(state.dailyRunCount)")
                infoRow(title: L.SettingsWakeup.failures, value: "\(state.consecutiveFailures)/\(CodexWakeupScheduler.maxConsecutiveFailures)")
            }
        }
    }

    private var historyCard: some View {
        SettingCard(
            icon: "clock.arrow.circlepath",
            iconColor: .blue,
            title: L.SettingsWakeup.history,
            hint: ""
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Button(L.SettingsWakeup.clearHistory) {
                        wakeupManager.clearHistory()
                    }
                    .disabled(wakeupManager.history.isEmpty)
                }

                if wakeupManager.history.isEmpty {
                    Text(L.SettingsWakeup.emptyHistory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(wakeupManager.history) { item in
                            historyRow(item)
                            if item.id != wakeupManager.history.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var accountRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundColor(canRunWakeup ? .green : .secondary)
            Text(L.SettingsWakeup.currentAccount)
                .foregroundColor(.secondary)
            Spacer()
            Text(currentAccount?.displayName ?? L.SettingsWakeup.noAccount)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusText: String {
        if wakeupManager.isRunning {
            return L.SettingsWakeup.running
        }
        if !wakeupManager.lastStatusMessage.isEmpty {
            return wakeupManager.lastStatusMessage
        }
        return L.SettingsWakeup.neverRun
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }

    private func historyRow(_ item: CodexWakeupHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(item.success ? .green : .red)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(triggerName(item.trigger))
                        .fontWeight(.medium)
                    Text(item.accountName)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(formattedDate(item.timestamp) ?? "")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Text(item.success ? L.SettingsWakeup.success : L.SettingsWakeup.failed)
                        .foregroundColor(item.success ? .green : .red)
                    if item.durationMs > 0 {
                        Text("\(item.durationMs)ms")
                            .foregroundColor(.secondary)
                    }
                    Text(item.message)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 7)
    }

    private func warningRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CodexWakeupSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { wakeupManager.settings[keyPath: keyPath] },
            set: { wakeupManager.settings[keyPath: keyPath] = $0 }
        )
    }

    private func triggerName(_ trigger: CodexWakeupTrigger) -> String {
        switch trigger {
        case .manual:
            return L.SettingsWakeup.manual
        case .quotaReset:
            return L.SettingsWakeup.quotaResetTrigger
        case .dailyTime:
            return L.SettingsWakeup.dailyTimeTrigger
        case .interval:
            return L.SettingsWakeup.intervalTrigger
        }
    }

    private func dailyTimeRow(_ index: Int) -> some View {
        HStack {
            Text(L.SettingsWakeup.dailyTimeSlot(index + 1))
                .foregroundColor(.secondary)
            Spacer()
            DatePicker(
                "",
                selection: dailyTimeBinding(index),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .frame(width: 120, alignment: .trailing)
        }
        .font(.caption)
    }

    private func dailyTimeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let times = CodexWakeupSettings.normalizedDailyTimes(wakeupManager.settings.dailyTimes)
                return date(for: times[index])
            },
            set: { newValue in
                var times = CodexWakeupSettings.normalizedDailyTimes(wakeupManager.settings.dailyTimes)
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                times[index] = CodexWakeupTime(
                    hour: components.hour ?? 0,
                    minute: components.minute ?? 0
                )
                wakeupManager.settings.dailyTimes = CodexWakeupSettings.normalizedDailyTimes(times)
            }
        )
    }

    private func date(for time: CodexWakeupTime) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
