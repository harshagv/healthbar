import Foundation

/// Today's water intake and the pacing maths behind MiniMe's nagging.
///
/// Pacing is pro-rata across the active window rather than a flat remainder:
/// "you're 800 ml behind" lands harder than "4.2 litres to go", and it gives
/// MiniMe something to be smug about at 11am instead of only at 22:00.
struct HydrationTracker {

    var goalML: Int
    var activeStartHour: Int
    var activeEndHour: Int

    private(set) var consumedML: Int = 0
    /// "yyyy-MM-dd" (local) — the day `consumedML` belongs to.
    private(set) var dayKey: String

    init(goalML: Int, activeStartHour: Int, activeEndHour: Int, now: Date = Date()) {
        self.goalML = goalML
        self.activeStartHour = activeStartHour
        self.activeEndHour = activeEndHour
        self.dayKey = HydrationTracker.key(for: now)
    }

    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: Intake

    mutating func log(_ amountML: Int) {
        consumedML = max(0, consumedML + amountML)
    }

    /// Restore persisted state on launch. Ignores a stale day so a Mac left
    /// asleep overnight doesn't resurrect yesterday's total.
    mutating func restore(consumedML: Int, dayKey: String, now: Date = Date()) {
        guard dayKey == HydrationTracker.key(for: now) else { return }
        self.consumedML = max(0, consumedML)
        self.dayKey = dayKey
    }

    /// Roll over at local midnight. Returns the finished day so the caller can
    /// push it into history before the counter resets.
    mutating func rolloverIfNeeded(now: Date = Date()) -> (day: String, totalML: Int)? {
        let key = HydrationTracker.key(for: now)
        guard key != dayKey else { return nil }
        let finished = (dayKey, consumedML)
        dayKey = key
        consumedML = 0
        return finished
    }

    // MARK: Progress

    var progress: Double {
        goalML > 0 ? min(Double(consumedML) / Double(goalML), 1) : 0
    }

    var goalReached: Bool { consumedML >= goalML }

    var remainingML: Int { max(0, goalML - consumedML) }

    // MARK: Pacing

    /// How far through the active window we are, 0…1.
    func elapsedFraction(at date: Date, calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let start = Double(activeStartHour * 60)
        let end = Double(activeEndHour * 60)
        guard end > start else { return 0 }
        return min(max((minutes - start) / (end - start), 0), 1)
    }

    /// Where you'd be if you'd paced evenly since the window opened.
    func targetML(at date: Date, calendar: Calendar = .current) -> Int {
        Int((Double(goalML) * elapsedFraction(at: date, calendar: calendar)).rounded())
    }

    /// Positive = behind schedule. Negative = ahead, and MiniMe will say so.
    func deficitML(at date: Date, calendar: Calendar = .current) -> Int {
        targetML(at: date, calendar: calendar) - consumedML
    }

    func isWithinActiveHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= activeStartHour && hour < activeEndHour
    }
}
