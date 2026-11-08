import SwiftUI

// Reminders: header with a + to add, then rows of
// name | time | done | flag. Double-click a name to rename it inline.
struct ReminderView: View {
    @ObservedObject var manager: ReminderManager
    @State private var adding = false
    @State private var newTitle = ""
    @State private var editingID: String?
    @State private var editText = ""
    @State private var hoveredID: String?

    var body: some View {
        switch manager.authorizationStatus {
        case .fullAccess:
            VStack(alignment: .leading, spacing: 4) {
                header
                if adding { addField }
                if manager.reminders.isEmpty && !adding {
                    Text("No reminders")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Palette.textSecondary)
                }
                ForEach(manager.reminders) { item in
                    row(item)
                }
                if !manager.trash.isEmpty { trashSection }
            }
        case .notDetermined:
            NStatusBanner(icon: "checklist", title: "Keep reminders at hand",
                          message: "NØTH shows and adds reminders from your lists.",
                          tint: Theme.Palette.accent,
                          actionTitle: "Allow Reminders Access") { manager.requestAccess() }
        default:
            NStatusBanner(icon: "checklist.unchecked", title: "Reminders access is off",
                          message: "Turn on NØTH in Privacy & Security › Reminders.",
                          actionTitle: "Open System Settings") { SystemSettingsLink.open("Privacy_Reminders") }
        }
    }

    private var header: some View {
        HStack {
            Text("Reminders")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Palette.textSecondary)
            Spacer()
            Button {
                adding.toggle()
                newTitle = ""
            } label: {
                Image(systemName: adding ? "xmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Palette.text)
            }
            .buttonStyle(.plain)
        }
    }

    private var addField: some View {
        TextField("New reminder", text: $newTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(Theme.Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.Palette.elevated))
            .onSubmit {
                manager.create(title: newTitle)
                newTitle = ""
                adding = false
            }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(spacing: 6) {
            if editingID == item.id {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Palette.text)
                    .onSubmit {
                        manager.rename(item, to: editText)
                        editingID = nil
                    }
            } else {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundColor(item.isCompleted ? .gray : .white)
                    .strikethrough(item.isCompleted)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editText = item.title
                        editingID = item.id
                    }
            }

            Spacer(minLength: 4)

            // Tap to cycle preset due times (this evening → tomorrow 9am →
            // next week → clear). No date picker — those misbehave in the
            // non-key notch panel; taps don't.
            Button { cycleDue(item) } label: {
                if let due = item.dueDate {
                    // Time when the reminder has one, otherwise the date — a
                    // date-only reminder rendered with .time reads "12:00 AM".
                    Text(item.dueHasTime
                            ? due.formatted(date: .omitted, time: .shortened)
                            : due.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Palette.textSecondary)
                } else {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.35))
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Set due time")

            Button {
                manager.setCompleted(item, completed: !item.isCompleted)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)

            Image(systemName: item.flagged ? "flag.fill" : "flag")
                .font(.system(size: 10))
                .foregroundColor(item.flagged ? .orange : Color(white: 0.35))

            // Delete appears on row hover to keep the narrow row uncluttered.
            if hoveredID == item.id {
                Button { manager.delete(item) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete (restorable from Trash)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
    }

    // Recently deleted reminders, restorable until they age out of the trash.
    private var trashSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.textSecondary)
                .padding(.top, 2)
            ForEach(manager.trash) { trashed in
                HStack(spacing: 6) {
                    Text(trashed.title)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Palette.textSecondary)
                        .strikethrough()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { manager.restore(trashed) } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Palette.text)
                    }
                    .buttonStyle(.plain)
                    .help("Restore")
                }
            }
        }
    }

    // Advance the reminder to the next preset due time; wraps to "clear".
    private func cycleDue(_ item: ReminderItem) {
        let presets: [Date?] = [Self.at(hour: 18, dayOffset: 0),   // this evening
                                Self.at(hour: 9, dayOffset: 1),    // tomorrow morning
                                Self.at(hour: 9, dayOffset: 7),    // next week
                                nil]                                // clear
        manager.setDue(item, to: DuePreset.next(after: item.dueDate, in: presets))
    }

    // A future clock time: `hour` today + `dayOffset` days.
    private static func at(hour: Int, dayOffset: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }
}
