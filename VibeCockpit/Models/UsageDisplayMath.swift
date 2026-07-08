import Foundation

public enum UsagePercentageDisplayMode: Equatable, Sendable {
    case used
    case remaining
}

public enum MenuBarMetricTextTone: Equatable, Sendable {
    case light
    case dark
}

public enum UsageDisplayMath {
    public static let defaultPopoverDisplayMode: UsagePercentageDisplayMode = .remaining
    public static let menuBarCircleRadiusInset = 2.4
    public static let menuBarCircleBackgroundLineWidth = 1.25
    public static let menuBarCircleProgressLineWidth = 2.0

    public static var defaultShowRemainingMode: Bool {
        defaultPopoverDisplayMode == .remaining
    }

    public static func clampedPercentage(_ percentage: Double) -> Double {
        min(100, max(0, percentage))
    }

    public static func remainingPercentage(fromUsedPercentage usedPercentage: Double) -> Double {
        100 - clampedPercentage(usedPercentage)
    }

    public static func displayPercentage(
        usedPercentage: Double,
        displayMode: UsagePercentageDisplayMode
    ) -> Double {
        switch displayMode {
        case .used:
            return clampedPercentage(usedPercentage)
        case .remaining:
            return remainingPercentage(fromUsedPercentage: usedPercentage)
        }
    }

    public static func integerTextPercentage(
        usedPercentage: Double,
        displayMode: UsagePercentageDisplayMode
    ) -> Int {
        Int(displayPercentage(usedPercentage: usedPercentage, displayMode: displayMode))
    }

    public static func menuBarMetricTextTone(isMonochrome: Bool) -> MenuBarMetricTextTone {
        isMonochrome ? .dark : .light
    }

    public static func menuBarMetricFontScale(isThreeDigit: Bool) -> Double {
        isThreeDigit ? 0.36 : 0.46
    }
}
