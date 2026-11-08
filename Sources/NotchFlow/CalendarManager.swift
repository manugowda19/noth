import EventKit

// Events for a selected day (defaults to today), via EventKit — fully public
// API, no private frameworks.
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var selectedDate = Calendar.current.startOfDay(for: Date()) {
        didSet { refreshIfAuthorized() }
    }

    private let store = EKEventStore()

    private init() {
        refreshIfAuthorized()

        // Event-driven refresh — fires when the user edits/adds events, or a
        // subscribed calendar syncs — instead of polling on a timer.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            // Re-read status too: a grant/revoke in System Settings while
            // running fires this, but doesn't otherwise update our copy.
            self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            self?.refreshIfAuthorized()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                if granted { self?.reloadEvents() }
            }
        }
    }

    private func refreshIfAuthorized() {
        guard authorizationStatus == .fullAccess else { return }
        reloadEvents()
    }

    private func reloadEvents() {
        let start = selectedDate
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        // events(matching:) is synchronous and can block on a large calendar —
        // fetch off-main, publish back.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let result = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            DispatchQueue.main.async { self.events = result }
        }
    }
}
