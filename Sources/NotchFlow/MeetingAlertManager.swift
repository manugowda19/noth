import AppKit
import EventKit
import Foundation

// "Meeting soon" alert: from 5 min before a timed event until 5 min after its
// start, the notch shows it and the shelf offers Join (when the event carries
// a Zoom/Meet/Teams/Webex/FaceTime link) and dismiss. Opt-in
// (`AppSettings.meetingAlerts`); reuses the calendar access CalendarManager
// already asked for. Own query, because CalendarManager only loads the day the
// user is browsing.
// ponytail: 30 s poll of a 10-minute window; EKEventStoreChanged isn't needed
// at this cadence.
final class MeetingAlertManager: ObservableObject {
    static let shared = MeetingAlertManager()

    @Published private(set) var alert: Meeting?

    private let store = EKEventStore()
    private var dismissed: Set<String> = []
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        alert = nil
    }

    func join() {
        guard let alert else { return }
        if let url = alert.joinURL { NSWorkspace.shared.open(url) }
        dismiss()
    }

    func dismiss() {
        guard let alert else { return }
        dismissed.insert(alert.id)
        self.alert = nil
    }

    private func poll() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            alert = nil
            return
        }
        let now = Date()
        // Covers both sides of the 5-minute lead/grace window.
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300),
                                                 end: now.addingTimeInterval(300), calendars: nil)
        let meetings = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate != nil }
            .map { event in
                Meeting(id: "\(event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "Meeting",
                        start: event.startDate,
                        joinURL: Meeting.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
            }
        let next = Meeting.alerting(meetings, now: now, dismissed: dismissed)
        if next != alert { alert = next }
    }
}
