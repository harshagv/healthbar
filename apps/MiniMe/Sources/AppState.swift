import Foundation
import SwiftUI
import Combine

/// View-model for the menu-bar panel. Owns settings (persisted to UserDefaults
/// via `didSet`), today's hydration, and the day-rollover clock.
///
/// Per the project's convention the whole thing lives on the main thread — no
/// `@MainActor` isolation, just the discipline of never mutating from anywhere
/// else. The status-item glyph is driven by `menuBarStep` (a 0…4 quantisation
/// of progress) rather than raw millilitres, so logging a glass redraws the
/// menu bar at most four times a day.
final class AppState: ObservableObject {

    private enum Keys {
        static let goalML       = "minimeDailyGoalML"
        static let logML        = "minimeLogAmountML"
        static let startHour    = "minimeActiveStartHour"
        static let endHour      = "minimeActiveEndHour"
        static let speech       = "minimeSpeechEnabled"
        static let voiceID      = "minimePersonalVoiceID"
        static let consumedML   = "minimeConsumedML"
        static let consumedDay  = "minimeConsumedDay"
    }

    // MARK: Settings

    @Published var dailyGoalML: Int {
        didSet {
            defaults.set(dailyGoalML, forKey: Keys.goalML)
            tracker.goalML = dailyGoalML
            refresh()
        }
    }

    @Published var logAmountML: Int {
        didSet { defaults.set(logAmountML, forKey: Keys.logML) }
    }

    @Published var activeStartHour: Int {
        didSet {
            defaults.set(activeStartHour, forKey: Keys.startHour)
            tracker.activeStartHour = activeStartHour
            eyeBreak.activeStartHour = activeStartHour
            refresh()
        }
    }

    @Published var activeEndHour: Int {
        didSet {
            defaults.set(activeEndHour, forKey: Keys.endHour)
            tracker.activeEndHour = activeEndHour
            eyeBreak.activeEndHour = activeEndHour
            refresh()
        }
    }

    /// Speech ships off — a voice is a great demo and grating by day three.
    @Published var speechEnabled: Bool {
        didSet { defaults.set(speechEnabled, forKey: Keys.speech) }
    }

    /// Which Personal Voice to speak with. Empty means "first one found".
    /// Two can be synced (iPhone and MacBook), hence a stored choice.
    @Published var personalVoiceID: String {
        didSet { defaults.set(personalVoiceID, forKey: Keys.voiceID) }
    }

    // MARK: Live state

    /// Set by `AppDelegate` so the panel does no work while it's closed.
    @Published var popoverIsOpen = false

    @Published private(set) var consumedML = 0
    @Published private(set) var deficitML = 0
    @Published private(set) var goalReached = false
    /// 0…4. Only this drives the menu-bar icon.
    @Published private(set) var menuBarStep = 0
    @Published private(set) var streak = 0

    let history = HistoryStore()

    private let defaults = UserDefaults.standard
    private var tracker: HydrationTracker
    private var tick: Timer?

    // MARK: Nudging

    private let overlay = CharacterOverlayController()
    private let eyeBreak = EyeBreakScheduler()
    private let dim = DimOverlayController()
    private var nudgeTimer: Timer?

    private let eyeBreakIntervalMinutes = 60.0
    private let breakSeconds = 20
    /// A skipped break gets one retry at +10 min, then the hour is forfeited —
    /// otherwise it's trivial to dismiss every break by reflex.
    private var breakRetried = false
    /// Snoozes stack, but only three times — then MiniMe stops being polite.
    private var consecutiveSnoozes = 0
    private let snoozeCap = 3
    /// Minutes between hydration nudges while the goal is still open.
    private let nudgeIntervalMinutes = 60.0

    init() {
        // Defaults chosen in the design pass: 5 L, 250 ml per log, 08:00–22:00.
        let goal  = defaults.object(forKey: Keys.goalML) as? Int ?? 5000
        let log   = defaults.object(forKey: Keys.logML) as? Int ?? 250
        let start = defaults.object(forKey: Keys.startHour) as? Int ?? 8
        let end   = defaults.object(forKey: Keys.endHour) as? Int ?? 22

        dailyGoalML     = goal
        logAmountML     = log
        activeStartHour = start
        activeEndHour   = end
        speechEnabled   = defaults.bool(forKey: Keys.speech)
        personalVoiceID = defaults.string(forKey: Keys.voiceID) ?? ""

        tracker = HydrationTracker(goalML: goal, activeStartHour: start, activeEndHour: end)
        tracker.restore(consumedML: defaults.integer(forKey: Keys.consumedML),
                        dayKey: defaults.string(forKey: Keys.consumedDay) ?? "")

        refresh()

        // One minute is plenty to catch midnight and keep the pacing deficit
        // current; anything finer would just wake the CPU for nothing.
        tick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        scheduleNextNudge(afterMinutes: nudgeIntervalMinutes)

        eyeBreak.activeStartHour = activeStartHour
        eyeBreak.activeEndHour = activeEndHour
        eyeBreak.intervalMinutes = eyeBreakIntervalMinutes
        eyeBreak.onDue = { [weak self] in self?.presentEyeBreak() }
        eyeBreak.start()
    }

    deinit {
        tick?.invalidate()
        nudgeTimer?.invalidate()
    }

    // MARK: Nudging

    /// Walk MiniMe in with whatever the day currently deserves.
    func summonMiniMe() {
        let beat = Persona.hydrationBeat(goalReached: goalReached, deficitML: deficitML)
        let line = Persona.line(beat, deficitML: deficitML)

        var actions: [CharacterAction] = [
            CharacterAction("Drank water!", isPrimary: true) { [weak self] in
                guard let self else { return }
                self.logWater()
                self.consecutiveSnoozes = 0
                // Crossing the goal earns a victory lap; an ordinary glass just
                // gets an acknowledgement and he sees himself out.
                if self.goalReached {
                    self.overlay.celebrate(message: Persona.line(.goalHit))
                } else {
                    self.overlay.celebrate(message: "Logged. \(self.litresRemainingLine)", duration: 2.2)
                }
                self.scheduleNextNudge(afterMinutes: self.nudgeIntervalMinutes)
            }
        ]

        // Past the cap there's nothing to negotiate with, so the snooze buttons
        // simply stop being offered.
        if consecutiveSnoozes < snoozeCap {
            actions.append(CharacterAction("+5 min") { [weak self] in self?.snooze(minutes: 5) })
            actions.append(CharacterAction("+10 min") { [weak self] in self?.snooze(minutes: 10) })
        }

        overlay.present(message: line, actions: actions, timeout: 30) { [weak self] in
            // Ignored rather than answered: a quiet miss, no penalty beyond
            // falling further behind pace.
            guard let self else { return }
            self.scheduleNextNudge(afterMinutes: self.nudgeIntervalMinutes)
        }
    }

    // MARK: Eye breaks

    var timeUntilNextBreak: TimeInterval? { eyeBreak.timeUntilNext }

    /// Ask first, dim second. The prompt *is* the warning, which is what keeps
    /// a break from swallowing whatever you were mid-way through typing.
    func presentEyeBreak() {
        var line = Persona.line(.breakEntrance)
        // When a hydration nudge and a break coincide, fold them into one
        // interruption rather than two.
        if !goalReached, deficitML > 50, isWithinActiveHours {
            line += " And you're \(deficitML) ml behind."
        }

        let actions = [
            CharacterAction("Take break now", isPrimary: true) { [weak self] in self?.startEyeBreak() },
            CharacterAction("+5 min") { [weak self] in self?.snoozeBreak(5) },
            CharacterAction("+10 min") { [weak self] in self?.snoozeBreak(10) }
        ]

        overlay.present(message: line, actions: actions, timeout: 30) { [weak self] in
            self?.eyeBreakIgnored()
        }
    }

    private func startEyeBreak() {
        overlay.dismiss()
        breakRetried = false
        dim.begin(seconds: breakSeconds, message: Persona.line(.breakEntrance)) { [weak self] taken in
            guard let self else { return }
            self.history.recordBreak(taken: taken, goalML: self.dailyGoalML)
            self.eyeBreak.scheduleNext(afterMinutes: taken ? self.eyeBreakIntervalMinutes : 10)
            if taken {
                self.overlay.present(message: Persona.line(.breakComplete), actions: [], timeout: 3.5)
            }
        }
    }

    private func snoozeBreak(_ minutes: Double) {
        overlay.dismiss()
        eyeBreak.scheduleNext(afterMinutes: minutes)
    }

    private func eyeBreakIgnored() {
        history.recordBreak(taken: false, goalML: dailyGoalML)
        eyeBreak.scheduleNext(afterMinutes: breakRetried ? eyeBreakIntervalMinutes : 10)
        breakRetried.toggle()
    }

    private var litresRemainingLine: String {
        let remaining = max(0, dailyGoalML - consumedML)
        return remaining == 0 ? "That's the lot." : String(format: "%.1f L to go.", Double(remaining) / 1000)
    }

    private func snooze(minutes: Double) {
        consecutiveSnoozes += 1
        overlay.dismiss()
        scheduleNextNudge(afterMinutes: minutes)
    }

    private func scheduleNextNudge(afterMinutes minutes: Double) {
        nudgeTimer?.invalidate()
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: false) { [weak self] _ in
            self?.fireNudgeIfAppropriate()
        }
    }

    private func fireNudgeIfAppropriate() {
        refresh()
        // Off the clock, or already done for the day — try again next cycle
        // rather than nagging into the evening.
        guard isWithinActiveHours, !goalReached else {
            scheduleNextNudge(afterMinutes: nudgeIntervalMinutes)
            return
        }
        summonMiniMe()
    }

    // MARK: Intake

    func logWater(_ ml: Int? = nil) {
        let amount = ml ?? logAmountML
        rolloverIfNeeded()
        tracker.log(amount)
        history.recordWater(amount, goalML: dailyGoalML)
        persistToday()
        refresh()
    }

    /// Undo a mis-tap. Never goes below zero.
    func removeWater(_ ml: Int? = nil) {
        let amount = ml ?? logAmountML
        rolloverIfNeeded()
        let actual = min(amount, tracker.consumedML)
        guard actual > 0 else { return }
        tracker.log(-actual)
        history.recordWater(-actual, goalML: dailyGoalML)
        persistToday()
        refresh()
    }

    var isWithinActiveHours: Bool { tracker.isWithinActiveHours(Date()) }

    // MARK: Derived

    private func rolloverIfNeeded() {
        guard let finished = tracker.rolloverIfNeeded() else { return }
        // Freeze the finished day at its true total before the counter resets.
        history.setWater(finished.totalML, goalML: dailyGoalML, dayKey: finished.day)
    }

    private func refresh() {
        rolloverIfNeeded()
        consumedML  = tracker.consumedML
        deficitML   = tracker.deficitML(at: Date())
        goalReached = tracker.goalReached
        streak      = history.currentStreak()

        let step = Int((tracker.progress * 4).rounded(.down))
        let clamped = min(max(step, 0), 4)
        if clamped != menuBarStep { menuBarStep = clamped }
    }

    private func persistToday() {
        defaults.set(tracker.consumedML, forKey: Keys.consumedML)
        defaults.set(tracker.dayKey, forKey: Keys.consumedDay)
    }
}
