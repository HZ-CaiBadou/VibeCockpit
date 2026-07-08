import Foundation
import VibeCockpitCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let now = Date(timeIntervalSince1970: 1_800)

let defaultSettings = CodexWakeupSettings()
check(defaultSettings.enabled == false, "wakeup should be disabled by default")
check(defaultSettings.wakeOnQuotaReset == true, "quota reset wakeup should default on once enabled")
check(defaultSettings.wakeOnDailyTimes == true, "daily time wakeup should default on once enabled")
check(defaultSettings.dailyTimes == [
    CodexWakeupTime(hour: 6, minute: 0),
    CodexWakeupTime(hour: 11, minute: 0),
    CodexWakeupTime(hour: 16, minute: 0)
], "daily time defaults should be 06:00, 11:00, 16:00")
check(defaultSettings.wakeOnInterval == false, "interval wakeup should default off")
check(defaultSettings.intervalHours == 4, "interval should default to 4 hours")
let settingsData = try JSONEncoder().encode(defaultSettings)
let decodedSettings = try JSONDecoder().decode(CodexWakeupSettings.self, from: settingsData)
check(decodedSettings == defaultSettings, "settings should round-trip through Codable")

check(UsageDisplayMath.clampedPercentage(-12) == 0, "display percentage should clamp negative values")
check(UsageDisplayMath.clampedPercentage(120) == 100, "display percentage should clamp values above 100")
check(UsageDisplayMath.remainingPercentage(fromUsedPercentage: 40) == 60, "menu bar should display remaining percentage from used percentage")
check(abs(UsageDisplayMath.remainingPercentage(fromUsedPercentage: 84.9) - 15.1) < 0.0001, "remaining percentage should preserve fractional input before integer drawing")
check(UsageDisplayMath.integerTextPercentage(usedPercentage: 84.9, displayMode: .remaining) == 15, "menu bar remaining label should truncate to remaining integer")
check(UsageDisplayMath.integerTextPercentage(usedPercentage: 84.9, displayMode: .used) == 84, "used label should preserve existing truncation")
check(UsageDisplayMath.defaultPopoverDisplayMode == .remaining, "status popover should default to remaining mode")
check(UsageDisplayMath.menuBarMetricTextTone(isMonochrome: false) == .light, "colored menu bar metric text should be white for dark menu bars")
check(UsageDisplayMath.menuBarMetricTextTone(isMonochrome: true) == .dark, "monochrome menu bar metric text should keep the template-safe dark tone")
check(UsageDisplayMath.menuBarCircleRadiusInset <= 2.5, "menu bar circle should be larger as a whole")
check(UsageDisplayMath.menuBarCircleProgressLineWidth >= 2.0, "menu bar circle stroke should scale with the larger icon")
check(UsageDisplayMath.menuBarMetricFontScale(isThreeDigit: false) >= 0.45, "two-digit menu bar metric text should stand out without crowding")
check(UsageDisplayMath.menuBarMetricFontScale(isThreeDigit: true) >= 0.35, "three-digit menu bar metric text should remain legible")

var state = CodexWakeupAccountState()
CodexWakeupScheduler.ensureIntervalAnchor(state: &state, now: now)
let intervalSettings = CodexWakeupSettings(enabled: true, wakeOnQuotaReset: false, wakeOnInterval: true, intervalHours: 4)
check(CodexWakeupScheduler.nextDecision(settings: intervalSettings, state: state, now: now, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false) == nil, "interval should not run immediately after enabling")
let later = now.addingTimeInterval(4 * 3600 + 1)
check(CodexWakeupScheduler.nextDecision(settings: intervalSettings, state: state, now: later, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false)?.trigger == .interval, "interval should run after interval hours")

let resetSettings = CodexWakeupSettings(enabled: true, wakeOnQuotaReset: true, wakeOnInterval: false, intervalHours: 4)
let resetAt = now.addingTimeInterval(-11)
let resetDecision = CodexWakeupScheduler.nextDecision(settings: resetSettings, state: state, now: now, primaryResetAt: resetAt, secondaryResetAt: resetAt, isRunning: false)
check(resetDecision == CodexWakeupDecision(trigger: .quotaReset, resetKey: "quota:\(Int(resetAt.timeIntervalSince1970))"), "quota reset should dedupe equal primary/secondary timestamps")
CodexWakeupScheduler.recordCompletion(state: &state, decision: resetDecision!, now: now, success: true)
check(CodexWakeupScheduler.nextDecision(settings: resetSettings, state: state, now: now.addingTimeInterval(31 * 60), primaryResetAt: resetAt, secondaryResetAt: resetAt, isRunning: false) == nil, "completed reset key should not run again")

var shanghaiCalendar = Calendar(identifier: .gregorian)
shanghaiCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
let dailySettings = CodexWakeupSettings(enabled: true, wakeOnQuotaReset: false, wakeOnDailyTimes: true, wakeOnInterval: false)
let dailyNow = Date(timeIntervalSince1970: 1_799_359_230) // 2027-01-08 06:00:30 +0800
let dailyDecision = CodexWakeupScheduler.nextDecision(settings: dailySettings, state: CodexWakeupAccountState(), now: dailyNow, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar)
check(dailyDecision == CodexWakeupDecision(trigger: .dailyTime, dailyTimeKey: "daily:2027-01-08:06:00"), "daily time should run when local hour and minute match")
let sameMinute = Date(timeIntervalSince1970: 1_799_359_259) // 2027-01-08 06:00:59 +0800
check(CodexWakeupScheduler.nextDecision(settings: dailySettings, state: CodexWakeupAccountState(), now: sameMinute, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar) == CodexWakeupDecision(trigger: .dailyTime, dailyTimeKey: "daily:2027-01-08:06:00"), "daily time should run anywhere inside the matching minute")
let nextMinute = Date(timeIntervalSince1970: 1_799_359_260) // 2027-01-08 06:01:00 +0800
check(CodexWakeupScheduler.nextDecision(settings: dailySettings, state: CodexWakeupAccountState(), now: nextMinute, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar) == nil, "daily time should not run after the configured minute")
var dailyState = CodexWakeupAccountState()
CodexWakeupScheduler.recordCompletion(state: &dailyState, decision: dailyDecision!, now: dailyNow, success: true, calendar: shanghaiCalendar)
let afterCooldown = dailyNow.addingTimeInterval(31 * 60)
check(CodexWakeupScheduler.nextDecision(settings: dailySettings, state: dailyState, now: afterCooldown, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar) == nil, "completed daily time should not run again for the same minute")
let outsideWindow = Date(timeIntervalSince1970: 1_799_370_000) // 2027-01-08 09:00:00 +0800
check(CodexWakeupScheduler.nextDecision(settings: dailySettings, state: CodexWakeupAccountState(), now: outsideWindow, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar) == nil, "daily time should not backfill hours later")

var manualBeforeDailyState = CodexWakeupAccountState()
let manualBeforeDaily = Date(timeIntervalSince1970: 1_799_359_155) // 2027-01-08 05:59:15 +0800
CodexWakeupScheduler.recordCompletion(state: &manualBeforeDailyState, decision: CodexWakeupDecision(trigger: .manual), now: manualBeforeDaily, success: true, calendar: shanghaiCalendar)
let manualThenDailyDecision = CodexWakeupScheduler.nextDecision(settings: dailySettings, state: manualBeforeDailyState, now: dailyNow, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar)
check(manualThenDailyDecision == CodexWakeupDecision(trigger: .dailyTime, dailyTimeKey: "daily:2027-01-08:06:00"), "manual test should not cool down a scheduled daily wakeup")

var autoBeforeDailyState = CodexWakeupAccountState()
CodexWakeupScheduler.recordCompletion(state: &autoBeforeDailyState, decision: CodexWakeupDecision(trigger: .quotaReset, resetKey: "quota:auto-test"), now: manualBeforeDaily, success: true, calendar: shanghaiCalendar)
let autoThenDailyDecision = CodexWakeupScheduler.nextDecision(settings: dailySettings, state: autoBeforeDailyState, now: dailyNow, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar)
check(autoThenDailyDecision == CodexWakeupDecision(trigger: .dailyTime, dailyTimeKey: "daily:2027-01-08:06:00"), "automatic wakeup cooldown should not block a matching daily time")

let cappedDailyState = CodexWakeupAccountState(
    lastAutomaticRunAt: manualBeforeDaily,
    dailyRunDay: 20270108,
    dailyRunCount: 8,
    consecutiveFailures: 3
)
let cappedDailyDecision = CodexWakeupScheduler.nextDecision(settings: dailySettings, state: cappedDailyState, now: dailyNow, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false, calendar: shanghaiCalendar)
check(cappedDailyDecision == CodexWakeupDecision(trigger: .dailyTime, dailyTimeKey: "daily:2027-01-08:06:00"), "matching daily time should not be blocked by quota/interval safety limits")

var capped = CodexWakeupAccountState(lastRunAt: nil, intervalAnchorAt: now.addingTimeInterval(-10_000), dailyRunDay: Int(floor(now.timeIntervalSince1970 / 86_400)), dailyRunCount: 8)
check(CodexWakeupScheduler.nextDecision(settings: intervalSettings, state: capped, now: now, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false) == nil, "daily cap should block wakeup")
capped.dailyRunCount = 0
capped.consecutiveFailures = 3
check(CodexWakeupScheduler.nextDecision(settings: intervalSettings, state: capped, now: now, primaryResetAt: nil, secondaryResetAt: nil, isRunning: false) == nil, "failure cap should block wakeup")

let sse = """
event: response.completed
data: {"response":{"output":[{"content":[{"type":"output_text","text":"OK"}]}]}}

"""
let reply = CodexWakeupResponseParser.replyText(from: Data(sse.utf8))
check(reply == "OK", "SSE response should extract OK")
check(CodexWakeupResponseParser.isSuccessfulWakeupReply(reply), "OK reply should be successful")
check(!CodexWakeupResponseParser.isSuccessfulWakeupReply("Nope"), "non-OK reply should fail validation")

let requestBody = CodexWakeupRequestBody.officialWakeup(prompt: "请回复 OK")
check(requestBody.model == "gpt-5.4", "official ChatGPT-account wakeup should default to gpt-5.4")
let requestData = try JSONEncoder().encode(requestBody)
let requestObject = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]
let requestInput = requestObject?["input"] as? [[String: Any]]
check(requestInput?.first?["type"] as? String == "message", "Codex Responses input item should declare message type")
check(requestObject?["instructions"] as? String == "", "Codex Responses wakeup payload should include empty instructions")

print("VibeCockpitCoreChecks passed")
