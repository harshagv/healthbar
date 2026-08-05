import Foundation

/// MiniMe's voice, as pure data.
///
/// Short, declarative, absurdly self-certain — never actually mean. Kept
/// separate from every behaviour so the tone can be rewritten without touching
/// a line of logic.
///
/// Lines are drawn from a shuffle bag per beat: nothing repeats until that
/// beat's bank is exhausted, which is what stops a character with 40 lines from
/// feeling like a character with 4.
enum Persona {

    enum Beat: Hashable {
        case onPace
        case behind
        case ahead
        case goalHit
        case breakEntrance
        case breakComplete
        case snooze5
        case snooze10
        case snoozeCap
        case rare
        case morning
        case lateNight
        case offHours
    }

    /// `{d}` is replaced with the deficit (or surplus) in millilitres,
    /// `{name}` with the user's first name.
    private static let bank: [Beat: [String]] = [
        .onPace: [
            "On schedule. As expected. I don't plan for other outcomes.",
            "Exactly where you should be. Coincidence? I don't believe in those.",
            "Nothing to report. That's the highest praise I give.",
            "You're on track. Don't let it go to your head — that's my job."
        ],
        .behind: [
            "{d} ml behind. Not a crisis. Not nothing, either.",
            "The schedule moved. You didn't. {d} ml.",
            "{d} ml behind. I've noticed. I always notice.",
            "Two choices: drink now, or hear from me in an hour. There is no third.",
            "{d} ml. I've stopped suggesting.",
            "I don't repeat myself. I'm making an exception. {d} ml."
        ],
        .ahead: [
            "Ahead of schedule. Even I didn't see that coming.",
            "{d} ml ahead. Showing off. I approve.",
            "Ahead of pace. Somebody's been taking me seriously."
        ],
        .goalHit: [
            "Target met. You can stop. I've never said that before — enjoy it.",
            "Done. The rest of today is a bonus round.",
            "Goal complete. I'll be quiet now. Savour it; it doesn't happen often.",
            "Announced once. Delivered once. That's the difference."
        ],
        .breakEntrance: [
            "Sixty minutes you stared. I gave you all sixty. Now I'm taking twenty seconds back.",
            "Screen's off. Eyes up. This part isn't a discussion.",
            "An hour of work. Twenty seconds of rent. Pay up.",
            "You didn't blink. I counted.",
            "The screen will wait. It always waits. Look at something far away.",
            "I walked all the way here. Least you can do is look out a window."
        ],
        .breakComplete: [
            "Twenty seconds. Cheapest deal you'll make today.",
            "Eyes reset. I'll see you in an hour. I always do.",
            "That's it. Painless, wasn't it. Say it wasn't — I'll wait.",
            "Done. Your eyes thanked me. You didn't have to."
        ],
        .snooze5: [
            "Five minutes. I'll wait. Waiting is undefeated.",
            "Five. I'm counting them out loud in my head."
        ],
        .snooze10: [
            "Ten minutes. Set your watch by me. Everyone else does.",
            "Ten. Generous. Don't mistake it for a pattern."
        ],
        .snoozeCap: [
            "Third snooze. There isn't a fourth.",
            "That was the last one. I'm not negotiating with a glass of water."
        ],
        .rare: [
            "Some people drink when they're thirsty. Amateurs. We drink on schedule.",
            "I don't nag. I remind. The difference is that I'm right.",
            "Hydration is not a personality. But it's a start.",
            "One day you'll do this without me. Not today.",
            "{name}. Water. Now. I've been polite for hours."
        ],
        .morning: [
            "Morning. The day's already got a target on it."
        ],
        .lateNight: [
            "It's late and I'm still here. That should tell you something."
        ],
        .offHours: [
            "I'm off the clock. Free advice: sleep."
        ]
    ]

    /// How often a `.behind` or `.onPace` nudge is swapped for a rare line.
    private static let rareChance = 0.12

    private static var bags: [Beat: [String]] = [:]

    /// Draw a line, substituting `{d}` and `{name}`.
    static func line(_ beat: Beat, deficitML: Int = 0, name: String = "Harsha") -> String {
        var beat = beat
        if (beat == .behind || beat == .onPace), Double.random(in: 0..<1) < rareChance {
            beat = .rare
        }

        guard let all = bank[beat], !all.isEmpty else { return "" }

        // Refill the bag when it runs dry, so every line is used once per cycle.
        if bags[beat]?.isEmpty ?? true {
            bags[beat] = all.shuffled()
        }
        let raw = bags[beat]?.popLast() ?? all[0]

        return raw
            .replacingOccurrences(of: "{d}", with: String(abs(deficitML)))
            .replacingOccurrences(of: "{name}", with: name)
    }

    /// The hydration beat that matches where the day actually is.
    static func hydrationBeat(goalReached: Bool, deficitML: Int, now: Date = Date()) -> Beat {
        if goalReached { return .goalHit }
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 9 { return .morning }
        if hour >= 22 { return .lateNight }
        if deficitML > 50 { return .behind }
        if deficitML < -50 { return .ahead }
        return .onPace
    }
}
