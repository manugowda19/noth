import SwiftUI
import EventKit

// One timeline for today (06:00 → midnight): a progress track filled to "now",
// with dots for timed calendar events (blue) and due reminders (orange). Reuses
// the existing Calendar + Reminder managers — no new data source.
// ponytail: fixed 06:00–24:00 window, no bedtime marker or source picker — add
// those if the flat timeline proves too blunt.
struct DayProgressView: View {
    @ObservedObject var calendar: CalendarManager
    @ObservedObject var reminders: ReminderManager

    private let startHour = 6
    private let spanHours: Double = 18   // 06:00 → 24:00

    private func fraction(_ date: Date) -> Double {
        let start = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: Date())
            ?? Date()
        return min(max(date.timeIntervalSince(start) / (spanHours * 3600), 0), 1)
    }

    private var eventMarks: [Double] {
        calendar.events.filter { !$0.isAllDay }.map { fraction($0.startDate) }
    }

    private var reminderMarks: [Double] {
        reminders.reminders.compactMap { item in
            guard item.dueHasTime, let due = item.dueDate,
                  Calendar.current.isDateInToday(due) else { return nil }
            return fraction(due)
        }
    }

    var body: some View {
        // Refresh the "now" marker every minute without a manual timer.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = fraction(context.date)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.interactive).frame(height: 4)
                    Capsule().fill(Theme.Palette.accent.opacity(0.6)).frame(width: w * now, height: 4)
                    ForEach(eventMarks.indices, id: \.self) { i in
                        Circle().fill(Theme.Palette.accent).frame(width: 5, height: 5)
                            .offset(x: w * eventMarks[i] - 2.5)
                    }
                    ForEach(reminderMarks.indices, id: \.self) { i in
                        Circle().fill(Theme.Palette.warning).frame(width: 5, height: 5)
                            .offset(x: w * reminderMarks[i] - 2.5)
                    }
                    Rectangle().fill(Color.white).frame(width: 1.5, height: 12)
                        .offset(x: w * now - 0.75)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 14)
        .safeAreaInset(edge: .top, spacing: 6) {
            HStack {
                Text("TODAY").font(Theme.Typo.eyebrow).kerning(0.6)
                    .foregroundColor(Theme.Palette.textSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Text("6 AM – midnight")
                    Circle().fill(Theme.Palette.accent).frame(width: 6, height: 6).padding(.leading, 4)
                    Text("events")
                    Circle().fill(Theme.Palette.warning).frame(width: 6, height: 6).padding(.leading, 4)
                    Text("reminders")
                }
                .font(Theme.Typo.caption).foregroundColor(Theme.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day progress")
        .accessibilityValue("\(Int(fraction(Date()) * 100)) percent of the day, \(eventMarks.count) events, \(reminderMarks.count) reminders")
    }
}
