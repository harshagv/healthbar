import SwiftUI
import Charts

/// The menu-bar panel. Deliberately shallow: read today's numbers, log a glass,
/// glance at the week. Anything that needs a decision lives in Settings.
struct MenuContentView: View {
    @ObservedObject var state: AppState

    private let sprites = SpriteLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            progress
            quickLog
            Divider()
            WeekChart(history: state.history, goalML: state.dailyGoalML)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 10) {
            if sprites.isLoaded {
                SpriteImageView(image: portrait)
                    .frame(height: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("MiniMe").font(.headline)
                Text(paceLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if state.streak > 0 {
                Label("\(state.streak)", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("\(state.streak)-day streak")
            }
        }
    }

    /// MiniMe's face reacts to how the day is going — it's the cheapest way to
    /// give the panel a mood without spending a line of dialogue on it.
    private var portrait: NSImage? {
        if state.goalReached { return sprites.shades }
        if !state.isWithinActiveHours { return sprites.neutral }
        let deficit = state.deficitML
        if deficit > 500 { return sprites.serious }
        if deficit > 50 { return sprites.thinking }
        if deficit < -50 { return sprites.wink }
        return sprites.smile
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(litres(state.consumedML))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of \(litres(state.dailyGoalML))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(state.consumedML), total: Double(max(state.dailyGoalML, 1)))
                .tint(state.goalReached ? .green : .accentColor)
        }
    }

    private var quickLog: some View {
        HStack(spacing: 8) {
            Button {
                state.logWater()
            } label: {
                Label("Log \(state.logAmountML) ml", systemImage: "drop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                state.removeWater()
            } label: {
                Image(systemName: "minus")
            }
            .controlSize(.large)
            .disabled(state.consumedML == 0)
            .help("Undo a mis-tap")
        }
    }

    private var footer: some View {
        HStack {
            Text(activeHoursLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Water") { state.summonMiniMe() }
                .buttonStyle(.link)
                .font(.caption)
                .help("Walk MiniMe in with a hydration nudge")
            Button("Eye break") { state.presentEyeBreak() }
                .buttonStyle(.link)
                .font(.caption)
                .help("Start an eye break now")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    // MARK: Copy

    private func litres(_ ml: Int) -> String {
        String(format: "%.1f L", Double(ml) / 1000)
    }

    private var paceLine: String {
        if state.goalReached { return "Goal hit. Nothing left to prove today." }
        if !state.isWithinActiveHours { return "Outside active hours — MiniMe is off the clock." }
        let deficit = state.deficitML
        if deficit > 50 { return "\(deficit) ml behind schedule." }
        if deficit < -50 { return "\(-deficit) ml ahead of schedule." }
        return "Right on pace."
    }

    private var activeHoursLine: String {
        guard let seconds = state.timeUntilNextBreak else {
            return String(format: "Active %02d:00–%02d:00", state.activeStartHour, state.activeEndHour)
        }
        let minutes = Int(seconds / 60)
        return minutes <= 0 ? "Eye break due" : "Eye break in \(minutes) min"
    }
}

/// The last seven days of intake. Split into its own view with its own
/// `@ObservedObject` because nested ObservableObjects don't propagate changes
/// through the parent on their own.
private struct WeekChart: View {
    @ObservedObject var history: HistoryStore
    let goalML: Int

    var body: some View {
        let days = history.lastDays(7, goalML: goalML)
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Day", day.shortWeekday),
                        y: .value("Litres", day.litres)
                    )
                    .foregroundStyle(day.goalReached ? Color.green : Color.accentColor)
                }
                RuleMark(y: .value("Goal", Double(goalML) / 1000))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 96)
        }
    }
}
