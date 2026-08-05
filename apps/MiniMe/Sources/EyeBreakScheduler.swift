import AppKit
import AVFoundation
import CoreGraphics

/// The 60-minute eye-break clock.
///
/// Deliberately conservative about *when* it's allowed to interrupt: outside
/// active hours, while you're away, or while the camera is live, the break is
/// pushed rather than fired. Pushing instead of skipping means a day spent in
/// meetings still ends with breaks taken, just later.
final class EyeBreakScheduler {

    var intervalMinutes: Double = 60
    var activeStartHour = 8
    var activeEndHour = 22
    /// Away this long and the clock stops — a break you weren't there for is
    /// worse than useless, because it resets the cycle for no benefit.
    var idlePauseMinutes: Double = 10
    /// How long to wait before re-checking when something defers a break.
    var deferMinutes: Double = 5

    /// Fired when a break is genuinely due. The owner decides what to show.
    var onDue: (() -> Void)?

    private var timer: Timer?
    private var nextDue: Date?
    private var wakeObserver: NSObjectProtocol?

    var timeUntilNext: TimeInterval? {
        guard let nextDue else { return nil }
        return max(0, nextDue.timeIntervalSinceNow)
    }

    func start() {
        scheduleNext(afterMinutes: intervalMinutes)

        // Waking from sleep restarts the cycle rather than firing instantly —
        // opening the lid shouldn't be greeted by a black screen.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.scheduleNext(afterMinutes: self.intervalMinutes)
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        nextDue = nil
    }

    func scheduleNext(afterMinutes minutes: Double) {
        nextDue = Date().addingTimeInterval(minutes * 60)
    }

    // MARK: Gating

    private func check() {
        guard let due = nextDue, Date() >= due else { return }

        if let reason = deferralReason() {
            _ = reason
            scheduleNext(afterMinutes: deferMinutes)
            return
        }

        onDue?()
    }

    /// Non-nil when a break is due but must not interrupt right now.
    private func deferralReason() -> String? {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < activeStartHour || hour >= activeEndHour { return "outside active hours" }
        if secondsIdle() > idlePauseMinutes * 60 { return "away from the keyboard" }
        if cameraInUse() { return "camera is live" }
        return nil
    }

    private func secondsIdle() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    /// A call in progress is the main thing worth deferring for. macOS exposes
    /// no public "screen is being shared" signal, so the camera stands in for
    /// it — it catches the meeting case, which is the one that actually hurts.
    private func cameraInUse() -> Bool {
        AVCaptureDevice.default(for: .video)?.isInUseByAnotherApplication ?? false
    }
}
