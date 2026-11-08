import EventKit

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    /// Whether the due date carries a time-of-day, or is a date only. Reminders
    /// commonly have date-only due dates, so a plain `.time` format would show
    /// a misleading "12:00 AM".
    let dueHasTime: Bool
    var isCompleted: Bool
    /// EKReminder has no "flagged" — priority stands in (any priority set).
    let flagged: Bool
}

// Reminders — a distinct EventKit entity type from calendar events, with its
// own authorization flow and async (callback-based) fetch API.
final class ReminderManager: ObservableObject {
    static let shared = ReminderManager()

    /// A soft-deleted reminder, kept briefly so it can be restored. EventKit has
    /// no un-delete, so restore re-creates it (title + due) in the default list.
    struct TrashedReminder: Identifiable {
        let id = UUID().uuidString
        let title: String
        let dueDate: Date?
    }

    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var trash: [TrashedReminder] = []
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    private let trashCap = 20
    /// A reminder that just came due — non-nil for ~5s so the notch companion
    /// can peek out with its title. Gated by `AppSettings.showCompanion`.
    @Published private(set) var justDue: ReminderItem?

    private let store = EKEventStore()
    private var firedIDs = Set<String>()
    private var dueTimer: Timer?

    private init() {
        refreshIfAuthorized()
        // Poll for newly-due reminders. 30s is plenty for a notch peek — a
        // reminder due "now" tolerates half a minute of slack.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        dueTimer = timer
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            // Re-read status too: a grant/revoke in System Settings while
            // running fires this, but doesn't otherwise update our copy.
            self?.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            self?.refreshIfAuthorized()
        }
    }

    func requestAccess() {
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                if granted { self?.reload() }
            }
        }
    }

    func setCompleted(_ item: ReminderItem, completed: Bool) {
        mutate(item) { $0.isCompleted = completed }
    }

    /// Rename an existing reminder (inline double-click edit).
    func rename(_ item: ReminderItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(item) { $0.title = trimmed }
    }

    /// Set (or clear) a reminder's due date. Writes hour/minute so `dueHasTime`
    /// is true and the companion can fire. ponytail: no EKAlarm — the user's
    /// Reminders notification settings still own alerts; we only set the date.
    func setDue(_ item: ReminderItem, to date: Date?) {
        mutate(item) { reminder in
            if let date {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: date)
            } else {
                reminder.dueDateComponents = nil
            }
        }
    }

    /// Delete a reminder, keeping a trashed copy for restore. Reminders syncs
    /// the removal system-wide via EventKit.
    func delete(_ item: ReminderItem) {
        let trashed = TrashedReminder(title: item.title, dueDate: item.dueDate)
        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let self,
                  let reminder = reminders?.first(where: { $0.calendarItemIdentifier == item.id })
            else { return }
            try? self.store.remove(reminder, commit: true)
            DispatchQueue.main.async {
                self.trash.insert(trashed, at: 0)
                if self.trash.count > self.trashCap { self.trash.removeLast() }
            }
            self.reload()
        }
    }

    /// Re-create a trashed reminder (title + due) in the default list.
    func restore(_ trashed: TrashedReminder) {
        guard let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trashed.title
        reminder.calendar = list
        if let due = trashed.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
        }
        try? store.save(reminder, commit: true)
        DispatchQueue.main.async { self.trash.removeAll { $0.id == trashed.id } }
        reload()
    }

    /// Create a reminder in the default list.
    func create(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = list
        try? store.save(reminder, commit: true)
        reload()
    }

    /// Fetch the live EKReminder for an item, apply a change, save, reload.
    private func mutate(_ item: ReminderItem, _ change: @escaping (EKReminder) -> Void) {
        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let reminder = reminders?.first(where: { $0.calendarItemIdentifier == item.id })
            else { return }
            change(reminder)
            try? self?.store.save(reminder, commit: true)
            self?.reload()
        }
    }

    private func refreshIfAuthorized() {
        guard authorizationStatus == .fullAccess else { return }
        reload()
    }

    private func reload() {
        // Incomplete only — a heavy Reminders account has hundreds of done
        // items; showing them all (sorted, strikethrough) is noise and slow.
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? [])
                .map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        dueHasTime: reminder.dueDateComponents?.hour != nil,
                        isCompleted: reminder.isCompleted,
                        flagged: reminder.priority > 0
                    )
                }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            let capped = Array(items.prefix(50)) // ponytail: 50 rows fit the notch; raise if anyone scrolls to the bottom
            DispatchQueue.main.async {
                self?.reminders = capped
                self?.checkDue()   // snappier than waiting up to 30s for the timer
            }
        }
    }

    /// Fire the companion for any reminder whose timed due date just passed.
    private func checkDue() {
        guard AppSettings.shared.showCompanion else { return }
        let now = Date()
        for item in reminders {
            guard item.dueHasTime, !item.isCompleted, let due = item.dueDate,
                  due <= now, due > now.addingTimeInterval(-3600), // ignore ancient overdue on launch
                  !firedIDs.contains(item.id)
            else { continue }
            firedIDs.insert(item.id)
            justDue = item
            let id = item.id
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if self?.justDue?.id == id { self?.justDue = nil }
            }
            break // one peek at a time
        }
    }
}
