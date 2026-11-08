import AppKit
import SwiftUI
import EventKit

// Calendar section: month + weekday block on the left, the 5-day strip
// (today ± 2) on the right, and the selected day's events below.
struct CalendarView: View {
    @ObservedObject var calendar: CalendarManager

    var body: some View {
        switch calendar.authorizationStatus {
        case .fullAccess:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    monthBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DateStripView(calendar: calendar)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let next = nextEvent {
                    countdownRow(next)
                }
                if calendar.events.isEmpty {
                    Text("No events")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Palette.textSecondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(calendar.events, id: \.eventIdentifier) { event in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(isOngoing(event) ? Color.green : Color.clear)
                                        .frame(width: 6, height: 6)
                                    Text(event.title)
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.Palette.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(event.isAllDay
                                            ? "All day"
                                            : event.startDate.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.Palette.textSecondary)
                                        .fixedSize()
                                }
                                .contentShape(Rectangle())
                                // Double-click opens it in Calendar.app — the
                                // native editor, rather than a cramped inline
                                // form for something with times and recurrence.
                                .onTapGesture(count: 2) { open(event) }
                            }
                        }
                    }
                }
            }
        case .notDetermined:
            NStatusBanner(icon: "calendar", title: "Show your day here",
                          message: "NØTH reads your calendars to show today's events and alerts.",
                          tint: Theme.Palette.accent,
                          actionTitle: "Allow Calendar Access") { calendar.requestAccess() }
        default:
            NStatusBanner(icon: "calendar.badge.exclamationmark", title: "Calendar access is off",
                          message: "Turn on NØTH in Privacy & Security › Calendars to see events.",
                          actionTitle: "Open System Settings") { SystemSettingsLink.open("Privacy_Calendars") }
        }
    }

    // The next upcoming event on the selected day (today only) — drives the
    // live countdown.
    private var nextEvent: EKEvent? {
        guard Calendar.current.isDateInToday(calendar.selectedDate) else { return nil }
        let now = Date()
        return calendar.events.first { !$0.isAllDay && $0.startDate > now }
    }

    // "Next: <title>  in 15 min" — the relative time auto-updates via SwiftUI.
    private func countdownRow(_ event: EKEvent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text(event.title)
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(event.startDate, style: .relative)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue)
                .fixedSize()
        }
    }

    // "Aug" in calendar-red with the weekday + day under it. Abbreviated, not
    // wide — the full month name ("August") wrapped in the narrow column.
    private var monthBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Date(), format: .dateTime.month(.abbreviated))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.red)
                .lineLimit(1)
            Text(Date(), format: .dateTime.weekday(.abbreviated).day())
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.textSecondary)
        }
    }

    private func isOngoing(_ event: EKEvent) -> Bool {
        let now = Date()
        return event.startDate <= now && now <= event.endDate
    }

    // There's no public per-event deep link into Calendar.app, so just open
    // the app (it lands on today's date). ponytail: opens Calendar, not the
    // exact event — no supported scheme targets one; revisit if Apple adds one.
    private func open(_ event: EKEvent) {
        if let cal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: cal, configuration: .init())
        }
    }
}

// Today ± 2 days; tapping a day loads that day's events.
private struct DateStripView: View {
    @ObservedObject var calendar: CalendarManager

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (-2...2).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                let isSelected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDate)
                Button {
                    calendar.selectedDate = Calendar.current.startOfDay(for: day)
                } label: {
                    VStack(spacing: 1) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 10))
                        Text(day, format: .dateTime.day())
                            .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    }
                    .frame(width: 21, height: 30)
                    .foregroundColor(isSelected ? .black : .white)
                    .background(isSelected ? Color.white : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
