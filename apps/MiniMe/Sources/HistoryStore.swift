import Foundation

/// Aggregated wellness stats for a single calendar day.
struct DayStat: Codable, Identifiable {
    let day: String          // "yyyy-MM-dd" (local)
    var waterML: Int
    var breaksTaken: Int
    var breaksSkipped: Int
    /// The goal in force on that day, so an old day still charts honestly after
    /// you move the target.
    var goalML: Int

    var id: String { day }
    var litres: Double { Double(waterML) / 1000 }
    var goalReached: Bool { goalML > 0 && waterML >= goalML }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var shortWeekday: String {
        guard let date = DayStat.parser.date(from: day) else { return day }
        return DayStat.weekday.string(from: date)
    }
}

/// Persists per-day aggregates across launches (UserDefaults JSON), pruned to
/// `retentionDays` so the defaults plist can't grow without bound.
final class HistoryStore: ObservableObject {

    @Published private(set) var days: [String: DayStat] = [:]

    private let key = "minimeHistoryDays"
    private let retentionDays = 90
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    static func dayKey(_ date: Date) -> String {
        HydrationTracker.key(for: date)
    }

    private func mutate(_ date: Date, goalML: Int, _ body: (inout DayStat) -> Void) {
        let k = HistoryStore.dayKey(date)
        var stat = days[k] ?? DayStat(day: k, waterML: 0, breaksTaken: 0, breaksSkipped: 0, goalML: goalML)
        stat.goalML = goalML
        body(&stat)
        days[k] = stat
        save()
    }

    func recordWater(_ ml: Int, goalML: Int, on date: Date = Date()) {
        mutate(date, goalML: goalML) { $0.waterML = max(0, $0.waterML + ml) }
    }

    /// Overwrite rather than accumulate — used when a day rolls over and we
    /// flush the final total, which may already be partly recorded.
    func setWater(_ ml: Int, goalML: Int, dayKey: String) {
        var stat = days[dayKey] ?? DayStat(day: dayKey, waterML: 0, breaksTaken: 0, breaksSkipped: 0, goalML: goalML)
        stat.waterML = max(0, ml)
        stat.goalML = goalML
        days[dayKey] = stat
        save()
    }

    func recordBreak(taken: Bool, goalML: Int, on date: Date = Date()) {
        mutate(date, goalML: goalML) {
            if taken { $0.breaksTaken += 1 } else { $0.breaksSkipped += 1 }
        }
    }

    /// The last `count` calendar days (oldest → newest), filling empty days so
    /// the chart never has gaps.
    func lastDays(_ count: Int, goalML: Int, now: Date = Date()) -> [DayStat] {
        let calendar = Calendar.current
        var result: [DayStat] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let k = HistoryStore.dayKey(date)
            result.append(days[k] ?? DayStat(day: k, waterML: 0, breaksTaken: 0, breaksSkipped: 0, goalML: goalML))
        }
        return result
    }

    /// Consecutive days meeting the goal, counting back from yesterday. Today
    /// is included only once it's actually won, so an unfinished day never
    /// breaks a live streak.
    func currentStreak(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var offset = 0
        if let todayStat = days[HistoryStore.dayKey(now)], todayStat.goalReached {
            streak += 1
        }
        offset = 1
        while true {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now),
                  let stat = days[HistoryStore.dayKey(date)],
                  stat.goalReached else { break }
            streak += 1
            offset += 1
        }
        return streak
    }

    func clear() {
        days = [:]
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: DayStat].self, from: data) else {
            return
        }
        days = decoded
    }

    private func prune() {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let cutoffKey = HistoryStore.dayKey(cutoff)
        days = days.filter { $0.key >= cutoffKey }   // "yyyy-MM-dd" sorts chronologically
    }

    private func save() {
        prune()
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: key)
        }
    }
}
